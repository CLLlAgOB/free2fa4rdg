# adminapi.py
# Copyright (C) 2024 Voloskov Aleksandr Nikolaevich

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

import aiosqlite
import os
import logging
from fastapi.middleware.cors import CORSMiddleware
from fastapi import FastAPI, HTTPException, Body, Depends, Security
from pydantic import BaseModel
from passlib.context import CryptContext
from datetime import datetime, timedelta
from jose import JWTError, jwt
from fastapi.security import OAuth2PasswordBearer, SecurityScopes
from typing import List
from sqlite3 import IntegrityError

# Logging Setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("free2fa4rdg_admin_api")

app = FastAPI()

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/admin", scopes={"admin": "Admin privileges"})
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


class ResetPasswordRequest(BaseModel):
    secret_key: str
    
class TokenData(BaseModel):
    username: str = None
    scopes: List[str] = []

class AdminAuth(BaseModel):
    username: str
    password: str

class PasswordChange(BaseModel):
    old_password: str
    new_password: str


SECRET_KEY = os.getenv("ADMIN_SECRET_KEY")
RESET_PASSWORD = os.getenv("RESET_PASSWORD", "false").lower() == "true"
del os.environ["ADMIN_SECRET_KEY"]

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

# Setting up CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all sources
    allow_credentials=True,
    allow_methods=["POST", "GET", "PUT", "DELETE"],  # Allows method
    allow_headers=["Content-Type", "Authorization"],  # Allows headers
)

# Model for user data
class UserUpdate(BaseModel):
    domain_and_username: str
    telegram_id: int
    is_bypass: bool

DATABASE_PATH = '/opt/db/users.db'


class User(BaseModel):
    domain_and_username: str
    telegram_id: int
    is_bypass: bool = False

async def generate_password_hash(password):
    return pwd_context.hash(password)

def create_access_token(data: dict, scopes: List[str]):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire, "scopes": scopes})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

async def authenticate_user(username: str, password: str):
    async with aiosqlite.connect(DATABASE_PATH) as db:
        async with db.execute('SELECT username, hashed_password FROM admins WHERE username = ?', (username,)) as cursor:
            admin = await cursor.fetchone()
            if admin and await verify_password(password, admin[1]):
                return {"username": admin[0]}
    return None

async def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

async def get_db():
    async with aiosqlite.connect(DATABASE_PATH) as db:
        yield db

async def init_db():
    async with aiosqlite.connect(DATABASE_PATH) as db:
        await db.execute('''
            CREATE TABLE IF NOT EXISTS users (
                domain_and_username TEXT PRIMARY KEY UNIQUE,
                telegram_id INTEGER,
                is_bypass BOOLEAN NOT NULL DEFAULT FALSE
            )
        ''')
        await db.commit()

@app.on_event("startup")

async def startup_event():
    await init_db()
    await init_admin_db() 

async def get_current_user(security_scopes: SecurityScopes, token: str = Depends(oauth2_scheme)):
    if token is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise HTTPException(status_code=401, detail="Invalid token")
        token_scopes = payload.get("scopes", [])
        token_data = TokenData(scopes=token_scopes, username=username)
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")

    if "admin" not in token_data.scopes:
        raise HTTPException(
            status_code=403,
            detail="Not enough permissions",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return token_data

@app.post("/users/")
async def add_user(user: User, current_user: User = Depends(get_current_user)):
    async with aiosqlite.connect(DATABASE_PATH) as db:
        try:
            await db.execute('INSERT INTO users (domain_and_username, telegram_id, is_bypass) VALUES (?, ?, ?)',
                             (user.domain_and_username, user.telegram_id, user.is_bypass))
            await db.commit()
            return {"message": "User added successfully"}
        except aiosqlite.IntegrityError:
            raise HTTPException(status_code=400, detail="User already exists")

@app.get("/users/")
async def get_all_users(current_user: User = Depends(get_current_user)):
    logger.info(f"get_all_users: ")
    async with aiosqlite.connect(DATABASE_PATH) as db:
        async with db.execute('SELECT * FROM users') as cursor:
            users = await cursor.fetchall()
            return users

@app.delete("/users/{domain_and_username}")
async def delete_user(domain_and_username: str, current_user: User = Depends(get_current_user)):
    async with aiosqlite.connect(DATABASE_PATH) as db:
        await db.execute('DELETE FROM users WHERE domain_and_username = ?', (domain_and_username,))
        await db.commit()
        return {"message": "User deleted successfully"}

@app.get("/verify-token")
async def verify_token(current_user: User = Depends(get_current_user)):
    return {"message": "Token is valid"}

# Function for user update
from sqlite3 import IntegrityError
from fastapi import HTTPException

@app.put("/users/{username}")
async def update_user(username: str, user_update: UserUpdate = Body(...), current_user: User = Depends(get_current_user)):
    logger.info(f"Updating user: {username}, {user_update} {Body ()}")
    try:
        logger.info(f"Received update data: {user_update.json()}")
        async with aiosqlite.connect(DATABASE_PATH) as db:
            # Checking user existence
            cursor = await db.execute('SELECT * FROM users WHERE domain_and_username = ?', (username,))
            existing_user = await cursor.fetchone()
            if not existing_user:
                raise HTTPException(status_code=404, detail="User not found")

            # Updating user data
            await db.execute('''
                UPDATE users SET domain_and_username = ?, telegram_id = ?, is_bypass = ? 
                WHERE domain_and_username = ?''',
                (user_update.domain_and_username, user_update.telegram_id, user_update.is_bypass, username)
            )
            await db.commit()

        return {"message": "User updated successfully"}

    except IntegrityError as e:
        if "UNIQUE constraint failed" in str(e):
            logger.error(f"Unique constraint error: {e}")
            raise HTTPException(status_code=400, detail="User with this domain_and_username already exists")
        else:
            logger.error(f"Database integrity error: {e}")
            raise HTTPException(status_code=500, detail="Database integrity error")

    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        raise HTTPException(status_code=500, detail="An unexpected error occurred")


@app.get("/users/{username}")
async def get_user(username: str, db=Depends(get_db), current_user: User = Depends(get_current_user)):
    async with db.execute('SELECT * FROM users WHERE domain_and_username = ?', (username,)) as cursor:
        user = await cursor.fetchone()
        if user:
            return {"domain_and_username": user[0], "telegram_id": user[1], "is_bypass": user[2]}
        else:
            raise HTTPException(status_code=404, detail="User not found")

@app.get("/health")
async def health_check():
    return {"status": "ok"}

async def init_admin_db():
    async with aiosqlite.connect(DATABASE_PATH) as db:
        await db.execute('''
            CREATE TABLE IF NOT EXISTS admins (
                username TEXT PRIMARY KEY,
                hashed_password TEXT,
                last_password_change DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        await db.commit()

        # Проверяем, существует ли уже пользователь admin
        async with db.execute('SELECT username FROM admins WHERE username = ?', ('admin',)) as cursor:
            if await cursor.fetchone() is None:
                # Добавляем администратора по умолчанию, если его еще нет
                default_admin = "admin"
                default_password_hash = await generate_password_hash("admin")
                await db.execute('INSERT INTO admins (username, hashed_password) VALUES (?, ?)',
                                 (default_admin, default_password_hash))
                await db.commit()


@app.post("/auth/admin")
async def admin_auth(admin_auth: AdminAuth):
    # Проверка пользователя
    user = await authenticate_user(admin_auth.username, admin_auth.password)
    if not user:
        raise HTTPException(status_code=401, detail="Incorrect username or password")
    # Создание токена
    access_token = create_access_token(data={"sub": user["username"]}, scopes=["admin"])
    return {"access_token": access_token, "token_type": "bearer"}


@app.post("/change-password")
async def change_password(password_change: PasswordChange, current_user: User = Security(get_current_user, scopes=["admin"])):
    # Проверка, что пользователь является администратором
    if current_user.username != "admin":
        raise HTTPException(status_code=403, detail="Not authorized to change password")

    async with aiosqlite.connect(DATABASE_PATH) as db:
        # Получение хешированного текущего пароля из базы данных
        async with db.execute('SELECT hashed_password FROM admins WHERE username = ?', (current_user.username,)) as cursor:
            current_hashed_password = await cursor.fetchone()

            if current_hashed_password is None:
                raise HTTPException(status_code=404, detail="User not found")

            # Проверка старого пароля
            if not pwd_context.verify(password_change.old_password, current_hashed_password[0]):
                raise HTTPException(status_code=403, detail="Old password is incorrect")

            # Обновление пароля
            new_hashed_password = await generate_password_hash(password_change.new_password)
            await db.execute('UPDATE admins SET hashed_password = ? WHERE username = ?', (new_hashed_password, current_user.username))
            await db.commit()

    return {"message": "Password changed successfully"}

@app.post("/reset-password")
async def reset_password(request: ResetPasswordRequest):
    secret_key = request.secret_key
    if not RESET_PASSWORD:
        raise HTTPException(status_code=403, detail="Password reset not enabled")

    if secret_key != SECRET_KEY:
        raise HTTPException(status_code=401, detail="Invalid secret key")

    # Сброс пароля админа на 'admin'
    new_hashed_password = await generate_password_hash("admin")
    async with aiosqlite.connect(DATABASE_PATH) as db:
        await db.execute('UPDATE admins SET hashed_password = ? WHERE username = ?', (new_hashed_password, "admin"))
        await db.commit()

    return {"message": "Password reset successfully"}

@app.get("/reset-password-enabled")
async def is_reset_password_enabled():
    return {"resetPasswordEnabled": RESET_PASSWORD}