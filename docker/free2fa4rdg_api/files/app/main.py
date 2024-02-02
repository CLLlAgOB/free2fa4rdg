# main.py
# Copyright (C) 2024 Voloskov Aleksandr Nikolaevich

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

import asyncio 
import aiosqlite
import time
import logging
import uvicorn
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from aiogram import Bot, types, Dispatcher
from aiogram.dispatcher.router import Router
from aiogram.filters import Command
from aiogram import exceptions as aiogram_exceptions
from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.types import Message
from config import Config


if Config.LANGUAGE == 'ru':
    import ru_ru as loc
elif Config.LANGUAGE == 'en':
    import en_en as loc
else:
    # default value if language is not defined
    import en_en as loc

router = Router()

# Limit the number of messages per second
MAX_MESSAGES_PER_SECOND = 28
message_count = 0 
message_count_lock = asyncio.Lock()
# FastAPI and aiogram initialization
app = FastAPI()
bot = Bot(token=Config.TOKEN)
dp = Dispatcher()
dp.include_router(router)

# Other dictionaries
search_state = {}
auth_requests = {}
last_message_info = {}

# Create a variable to store client_key
stored_client_key = None

#Server Responses
def response_200():
    return JSONResponse(status_code=200, content={"message": "OK"})
def response_403():
    return JSONResponse(status_code=403, content={"message": "Forbidden"})
def response_404():
    return JSONResponse(status_code=403, content={"message": "Not Found"})
def response_408():
    return JSONResponse(status_code=403, content={"message": "Timeout"})
       
# Defining a Pydantic model class for a query
class AuthorizeRequest(BaseModel):
    user_name: str
    client_key: str

class AuthenticateRequest(BaseModel):
    user_name: str
    client_key: str

# Bot and application configuration
DATABASE_PATH = '/opt/db/users.db'


logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger("free2fa4rdg")

#=============DB============
    
async def find_user_by_domain(domain_and_username):
    logger.debug(f"Search for a user with the name: {domain_and_username}") 
    async with aiosqlite.connect(DATABASE_PATH) as db:
        logger.debug("Successful connection to the database") 
        async with db.execute('SELECT telegram_id, is_bypass FROM users WHERE domain_and_username = ?', (domain_and_username,)) as cursor:
            result = await cursor.fetchone()
            if result:
                telegram_id, is_bypass = result
                logger.debug(f"Found User: {domain_and_username} tg id: {telegram_id} is_bypass: {is_bypass}")
                return telegram_id, is_bypass
            else:
                logger.warning(f"User {domain_and_username} not found")
            return None, None


async def create_new_user(domain_and_username, telegram_id, is_bypass=False):
    async with aiosqlite.connect(DATABASE_PATH) as db:
        try:
            await db.execute('INSERT INTO users (domain_and_username, telegram_id, is_bypass) VALUES (?, ?, ?)',
                             (domain_and_username, telegram_id, is_bypass))
            await db.commit()
            return True
        except aiosqlite.IntegrityError:
            return False


###====api===

@app.post("/authenticate")
async def authorize_user(request: AuthenticateRequest):
    global stored_client_key
    client_key = request.client_key
    # Checking API KEY
    if client_key != stored_client_key:
        logger.warning("Incorrect API_KEY") 
        return response_404()
    if request.user_name is not None:
        normalized_username = request.user_name.lower()
    else:
        # user_name missing
        return response_404()
    logger.debug(f"app.post authenticate  User verification: {normalized_username}")
    telegram_id, is_bypass = await find_user_by_domain(normalized_username)
    logger.debug(f"app.post authenticate  Found Telegram ID: {telegram_id}")
    if is_bypass:
        logger.info(f"Authentication request bypassed by user {normalized_username}")
        return response_200()
    if telegram_id and telegram_id != 0:
        wait_time = 1  # Waiting time

        # Waiting for a change of state or reaching the maximum waiting time
        while wait_time <= Config.FREE2FA_TIMEOUT and auth_requests.get(normalized_username) is None:
            logger.debug(f"Waiting for a response for {normalized_username} seconds {wait_time} from {Config.FREE2FA_TIMEOUT}")
            await asyncio.sleep(1)
            wait_time += 1
        # Checking the status of the request after waiting
        if normalized_username in auth_requests:
            if auth_requests[normalized_username]:
                logger.info(f"Authentication request accepted by user {normalized_username}")
                asyncio.create_task(clear_auth_request(normalized_username))
                return response_200()
            else:
                logger.info(f"Authentication request rejected by user {normalized_username}")
                asyncio.create_task(clear_auth_request(normalized_username))
                return response_403()
        else:
            logger.info(f"Authentication request timeout for user: {normalized_username}")
            asyncio.create_task(clear_auth_request(normalized_username))
            return response_408()
    else:
        if Config.BYPASS_ENABLED and telegram_id == 0 :
            logger.info(f"app.post authenticate  Bypass 2fa user: {normalized_username}")
            return response_200()
        raise response_404()


@app.post("/authorize")
async def authorize_user(request: AuthorizeRequest):
    global stored_client_key
    client_key = request.client_key

    # Checking and saving API KEY
    if stored_client_key is None:
        stored_client_key = client_key
        logger.info("Install API_KEY done.")

    if client_key != stored_client_key:
        logger.warning("Wrong API_KEY") 
        return response_404()
    if request.user_name is not None:
        normalized_username = request.user_name.lower()
    else:
        # user_name is missing
        return response_404()
    telegram_id, is_bypass = await find_user_by_domain(normalized_username)
    logger.debug(f"Start for {normalized_username} found Telegram ID: {telegram_id}")
    if is_bypass:
        logger.debug(f"Bypass user: {normalized_username}")
        return response_200()
    if telegram_id and telegram_id != 0:
        await send_auth_request(telegram_id, normalized_username)
        return response_200()
    else:
        if Config.AUTO_REG_ENABLED:
            logger.debug(f"Auto registration user: {normalized_username}")
            await create_new_user(normalized_username, 0)
            telegram_id = 0
            return response_200()
        logger.warning("User not found")
        raise response_404()


#==========BOT================
@router.message(Command(commands=['start']))
async def cmd_start(message: types.Message):
    user_telegram_id = message.from_user.id
    logger.info(f"{user_telegram_id} request /start")
    start_message = loc.MESSAGES["start"].format(user_telegram_id) + " " + loc.MESSAGES["register_with_admin"]
    await answer_limited_message(message, start_message)



# When sending an authorization request
async def send_auth_request(telegram_id, domain_and_username):
    normalized_username = domain_and_username.lower()
    current_time = time.time()
    if normalized_username in last_message_info:
        last_time, message_id, message_task = last_message_info[normalized_username]
        result = int(current_time - last_time)
        if result < Config.FREE2FA_TIMEOUT:
            # If the message was sent less than X seconds ago, skip sending a new one
            logger.info(f"{normalized_username} {result} Block new msg")
            return
    logger.info(f"Sending an authorization request for {normalized_username} telegram id {telegram_id} ")
    markup = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=loc.MESSAGES["action_accept"], callback_data=f"permit:{normalized_username}"),
         InlineKeyboardButton(text=loc.MESSAGES["action_reject"], callback_data=f"reject:{normalized_username}")]
    ])

    # Sending a new message and saving the sending time
    try:
        sent_message = await send_limited_message(telegram_id, loc.MESSAGES["auth_request"], markup)
        message_task = asyncio.create_task(
            send_message_after_delay(
                telegram_id,
                Config.FREE2FA_TIMEOUT + 1,
                loc.MESSAGES["was_auth_request"].format(domain_and_username),
                normalized_username,
                sent_message.message_id
            )
        )
        logger.debug(f"last_message_info for {normalized_username}")
        last_message_info[normalized_username] = (current_time, sent_message.message_id, message_task)
    except aiogram_exceptions.TelegramBadRequest as e:
        logger.warning(f"TelegramBadRequest while sending message to {telegram_id}: {e}")
    except Exception as e:
        logger.warning(f"Error when sending message: {e}")
        if "ClientConnectorError" in str(e) and Config.ALLOW_API_FAILURE_PASS:
            auth_requests[normalized_username] = True
            logger.warning(f"Allow access [{normalized_username}] by API failure ClientConnectorError")
    
async def delete_message(chat_id, message_id):
    try:
        await delete_limited_message(chat_id, message_id)
    except aiogram_exceptions.TelegramBadRequest as e:
        logger.exception(f"TelegramBadRequest: {e}")
    except Exception as e:
        logger.exception(f"Error in process_auth_response: {e}")

async def send_message_after_delay(chat_id, delay, message_text, normalized_username, message_id):
    await asyncio.sleep(delay)
    try:
        await send_limited_message(chat_id, message_text)
        await delete_message(chat_id, message_id)
        auth_requests[normalized_username] = False
        asyncio.create_task(clear_auth_request(normalized_username))
    except Exception as e:
        logger.exception(f"Error when sending message after delay: {e}")


@router.callback_query(lambda c: c.data.startswith("permit:") or c.data.startswith("reject:"))
async def process_auth_response(callback_query: types.CallbackQuery):
    try:
        action, domain_and_username = callback_query.data.split(':')
        normalized_username = domain_and_username.lower()
        logger.debug(f"router.callback_query Response Processing for: {normalized_username}, action: {action}")
        auth_requests[normalized_username] = (action == "permit")
        logger.debug(f"router.callback_query State of auth_requests after response processing: {auth_requests}")
        chat_id=callback_query.from_user.id
        message_id=callback_query.message.message_id
        await send_limited_edit_message(chat_id, message_id, None)
            
        if normalized_username in last_message_info:
            last_info = last_message_info[normalized_username]
            message_task = last_info[2] 

            if message_task:
                message_task.cancel()
            if action == "reject":
                logger.debug("router.callback_query Action=reject:")
            if action == "permit":
                logger.debug("router.callback_query Action=permit:")
                await delete_message(callback_query.from_user.id, callback_query.message.message_id)
            last_message_info[normalized_username] = (time.time()-Config.FREE2FA_TIMEOUT, last_info[1], None)

    except Exception as e:
        logger.exception(f"Error in process_auth_response: {e}")



async def clear_auth_request(domain_and_username, delay=1):
    await asyncio.sleep(delay)
    if domain_and_username in auth_requests:
        del auth_requests[domain_and_username]
        logger.info(f"Authorization for {domain_and_username} cleared.")

@app.get("/health")
async def health_check():
    return response_200()

#=======limits=============

async def reset_message_count():
    global message_count
    while True:
        await asyncio.sleep(1)
        message_count = 0

async def wait_for_message_slot():
    global message_count
    async with message_count_lock:  
        while message_count >= MAX_MESSAGES_PER_SECOND:
            logger.info(f"Warning!!! Message hold: {message_count}/{MAX_MESSAGES_PER_SECOND}")
            await asyncio.sleep(1)
        message_count += 1

async def send_limited_message(chat_id, text, reply_markup=None):
    await wait_for_message_slot()
    return await bot.send_message(chat_id, text, reply_markup=reply_markup)


async def answer_limited_message(message, text):
    await wait_for_message_slot()
    return await message.answer(text)

async def send_limited_edit_message(chat_id, message_id, reply_markup=None):
    await wait_for_message_slot()
    return await bot.edit_message_reply_markup(chat_id, message_id, reply_markup=reply_markup)       

async def delete_limited_message(chat_id, message_id):
    await wait_for_message_slot()
    return await bot.delete_message(chat_id, message_id)

#=========================================================

# Bot launch function
async def start_aiogram():
    try:
        await dp.start_polling(bot)
    except aiogram_exceptions.TelegramNetworkError as e:
        logger.warning(f"Telegram network error: {e}")
    except Exception as e:
        logger.error(f"Unhandled exception: {e}")


# Launch FastAPI and aiogram in one event loop
async def main():
    reset_task = asyncio.create_task(reset_message_count())
    loop = asyncio.get_event_loop()
    loop.create_task(start_aiogram())
    config = uvicorn.Config(
        app=app, 
        host="0.0.0.0", 
        port=5000, 
        loop=loop,
        ssl_keyfile='/app/certs/free2fa4rdg_api.key', 
        ssl_certfile='/app/certs/free2fa4rdg_api.crt'
    )
    server = uvicorn.Server(config)
    await server.serve()

if __name__ == "__main__":
    asyncio.run(main())
