
# ============================================================
# 💊 بوت تذكير الأدوية - Medication Reminder Bot
# ============================================================
# Architecture: Telegram Polling + Gradio Dashboard + JSON DB
# Language: Iraqi Arabic for patients
# Deployment: HuggingFace Spaces (Free)
# ============================================================

import json
import gradio as gr
import threading
import requests
import time
import os
from datetime import datetime, timedelta


# ============================================================
# 🔐 ENVIRONMENT VARIABLES - Never hardcode secrets!
# ============================================================
BOT_TOKEN  = os.environ.get("BOT_TOKEN", "")
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "1234")   # change in HF secrets

BASE_URL = f"https://api.telegram.org/bot{BOT_TOKEN}"


# ============================================================
# 📁 DATA FILE PATHS
# ============================================================
PATIENTS_FILE   = "patients.json"     # { chat_id: { name, medications: [...] } }
TAKEN_LOG_FILE  = "taken_log.json"    # { date: { chat_id: [med_id, ...] } }
STATS_FILE      = "stats.json"        # bot stats


# ============================================================
# 📊 GLOBAL STATE
# ============================================================
bot_stats = {
    "messages_received": 0,
    "reminders_sent": 0,
    "start_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    "active_users": set(),
}

conversation_history = {}   # chat_id -> list of messages (for AI)


# ============================================================
# 💾 JSON DATABASE HELPERS
# ============================================================

def load_patients():
    """Load all patients and their medications from file."""
    try:
        if os.path.exists(PATIENTS_FILE):
            with open(PATIENTS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception as e:
        print(f"[load_patients] Error: {e}")
    return {}


def save_patients(data):
    """Save patients data to file."""
    try:
        with open(PATIENTS_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"[save_patients] Error: {e}")


def load_taken_log():
    """Load the medication taken log."""
    try:
        if os.path.exists(TAKEN_LOG_FILE):
            with open(TAKEN_LOG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception as e:
        print(f"[load_taken_log] Error: {e}")
    return {}


def save_taken_log(data):
    """Save the medication taken log."""
    try:
        with open(TAKEN_LOG_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"[save_taken_log] Error: {e}")


def load_stats_file():
    """Load persistent stats."""
    try:
        if os.path.exists(STATS_FILE):
            with open(STATS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception:
        pass
    return {"total_reminders": 0, "total_messages": 0}


def save_stats_file(data):
    try:
        with open(STATS_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception:
        pass


# ============================================================
# 🤖 GROQ AI - Iraqi Arabic Medical Assistant
# ============================================================

SYSTEM_PROMPT = """
أنت مساعد طبي ذكي خاص ببوت تذكير الأدوية.
اسمك "دكتور بوت" 🤖💊

القواعد الأساسية:
- تكلم بالعربي العراقي الواضح والبسيط
- ردودك قصيرة ومفيدة
- استخدم إيموجي بشكل مناسب
- تذكر دايماً إنك مو بديل عن الدكتور الحقيقي
- إذا السؤال طبي خطير، قول للمريض يراجع الطبيب فوراً
- ساعد بالأسئلة البسيطة عن الأدوية والتوقيتات
- كن ودود ومشجع للمريض

أمثلة على ردودك:
- "أهلاً بيك! 😊 شلون أقدر أساعدك اليوم؟"
- "بالنسبة لسؤالك، الأفضل تسأل طبيبك المعالج 🏥"
- "لا تنسى تاخذ دواءك بالوقت المحدد يا بطل! 💪"
"""

def ask_groq(chat_id, user_message):
    """Send message to Groq AI and get response in Iraqi Arabic."""
    try:
        if not GROQ_API_KEY:
            return "مرحبا! 😊 أنا دكتور بوت. للأسف خدمة الذكاء الاصطناعي مو مفعلة هسه، بس أقدر أساعدك بإدارة أدويتك! استخدم /menu لشوف الخيارات."

        # Init history
        if chat_id not in conversation_history:
            conversation_history[chat_id] = []

        # Append user message
        conversation_history[chat_id].append({
            "role": "user",
            "content": user_message
        })

        # Keep last 10 turns only
        if len(conversation_history[chat_id]) > 20:
            conversation_history[chat_id] = conversation_history[chat_id][-20:]

        payload = {
            "model": "llama-3.3-70b-versatile",
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT}
            ] + conversation_history[chat_id],
            "max_tokens": 300,
            "temperature": 0.7,
        }

        headers = {
            "Authorization": f"Bearer {GROQ_API_KEY}",
            "Content-Type": "application/json",
        }

        resp = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            json=payload,
            headers=headers,
            timeout=15,
        )

        data = resp.json()
        assistant_reply = data["choices"][0]["message"]["content"].strip()

        # Save assistant reply to memory
        conversation_history[chat_id].append({
            "role": "assistant",
            "content": assistant_reply
        })

        return assistant_reply

    except Exception as e:
        print(f"[ask_groq] Error: {e}")
        return "معذرة، صارت مشكلة تقنية بسيطة 😅 حاول مرة ثانية بعد شوية!"


# ============================================================
# 📱 TELEGRAM API FUNCTIONS
# ============================================================

def send_message(chat_id, text, reply_markup=None, parse_mode="HTML"):
    """Send a text message to a Telegram user."""
    try:
        payload = {
            "chat_id": chat_id,
            "text": text,
            "parse_mode": parse_mode,
        }
        if reply_markup:
            payload["reply_markup"] = json.dumps(reply_markup)

        resp = requests.post(f"{BASE_URL}/sendMessage", json=payload, timeout=10)
        return resp.json()
    except Exception as e:
        print(f"[send_message] Error: {e}")
        return None


def send_typing(chat_id):
    """Show typing indicator."""
    try:
        requests.post(f"{BASE_URL}/sendChatAction", json={
            "chat_id": chat_id,
            "action": "typing"
        }, timeout=5)
    except Exception:
        pass


def answer_callback(callback_id, text="✅"):
    """Acknowledge a callback query."""
    try:
        requests.post(f"{BASE_URL}/answerCallbackQuery", json={
            "callback_query_id": callback_id,
            "text": text,
        }, timeout=5)
    except Exception:
        pass


def edit_message(chat_id, message_id, text, reply_markup=None):
    """Edit an existing message."""
    try:
        payload = {
            "chat_id": chat_id,
            "message_id": message_id,
            "text": text,
            "parse_mode": "HTML",
        }
        if reply_markup:
            payload["reply_markup"] = json.dumps(reply_markup)
        requests.post(f"{BASE_URL}/editMessageText", json=payload, timeout=10)
    except Exception as e:
        print(f"[edit_message] Error: {e}")


def get_updates(offset=None):
    """Fetch new updates from Telegram."""
    try:
        params = {"timeout": 20, "allowed_updates": ["message", "callback_query"]}
        if offset:
            params["offset"] = offset
        resp = requests.get(f"{BASE_URL}/getUpdates", params=params, timeout=25)
        return resp.json().get("result", [])
    except Exception as e:
        print(f"[get_updates] Error: {e}")
        return []


# ============================================================
# 💊 MEDICATION HELPERS
# ============================================================

def get_today_str():
    return datetime.now().strftime("%Y-%m-%d")


def is_med_taken_today(chat_id, med_id):
    """Check if a medication was marked taken today."""
    log = load_taken_log()
    today = get_today_str()
    return med_id in log.get(today, {}).get(str(chat_id), [])


def mark_med_taken(chat_id, med_id):
    """Mark a medication as taken today."""
    log = load_taken_log()
    today = get_today_str()
    if today not in log:
        log[today] = {}
    key = str(chat_id)
    if key not in log[today]:
        log[today][key] = []
    if med_id not in log[today][key]:
        log[today][key].append(med_id)
    save_taken_log(log)


def get_expiry_status(expiry_date_str):
    """Return expiry status: ok / warning / expired."""
    try:
        expiry = datetime.strptime(expiry_date_str, "%Y-%m-%d")
        now = datetime.now()
        diff = (expiry - now).days
        if diff < 0:
            return "expired", diff
        elif diff <= 30:
            return "warning", diff
        else:
            return "ok", diff
    except Exception:
        return "unknown", 0


def format_med_card(med, chat_id):
    """Format a single medication card for Telegram."""
    status, days = get_expiry_status(med.get("expiry", ""))
    taken = is_med_taken_today(chat_id, med["id"])

    expiry_icon = "✅" if status == "ok" else ("⚠️" if status == "warning" else "❌")
    taken_icon  = "✅ أخذته اليوم" if taken else "⏳ ما أخذته بعد"

    times_str = "، ".join(med.get("times", []))

    lines = [
        f"💊 <b>{med['name']}</b>",
        f"📋 الجرعة: {med.get('dosage', '-')}",
        f"🕐 أوقات التذكير: {times_str}",
        f"{expiry_icon} انتهاء الصلاحية: {med.get('expiry', '-')}",
    ]

    if status == "warning":
        lines.append(f"⚠️ <b>تنبيه: باقي {days} يوم للانتهاء!</b>")
    elif status == "expired":
        lines.append(f"❌ <b>الدواء منتهي الصلاحية منذ {abs(days)} يوم!</b>")

    if med.get("notes"):
        lines.append(f"📝 ملاحظات: {med['notes']}")

    lines.append(f"\n{taken_icon}")
    return "\n".join(lines)


# ============================================================
# 📋 INLINE KEYBOARD BUILDERS
# ============================================================

def main_menu_keyboard():
    return {
        "inline_keyboard": [
            [{"text": "💊 أدويتي", "callback_data": "my_meds"},
             {"text": "✅ سجل أخذ دواء", "callback_data": "take_med"}],
            [{"text": "📅 ملخص الأسبوع", "callback_data": "weekly_summary"},
             {"text": "⚠️ منتهية الصلاحية", "callback_data": "expiry_check"}],
            [{"text": "🤖 اسأل دكتور بوت", "callback_data": "ask_ai"},
             {"text": "ℹ️ مساعدة", "callback_data": "help"}],
        ]
    }


def meds_list_keyboard(medications, chat_id, for_taking=False):
    """Build keyboard listing all medications."""
    buttons = []
    for med in medications:
        taken = is_med_taken_today(chat_id, med["id"])
        prefix = "✅ " if taken else "💊 "
        callback = f"take_{med['id']}" if for_taking else f"med_detail_{med['id']}"
        buttons.append([{"text": f"{prefix}{med['name']}", "callback_data": callback}])
    buttons.append([{"text": "🏠 القائمة الرئيسية", "callback_data": "main_menu"}])
    return {"inline_keyboard": buttons}


def back_keyboard():
    return {
        "inline_keyboard": [
            [{"text": "🏠 القائمة الرئيسية", "callback_data": "main_menu"}]
        ]
    }


# ============================================================
# 🚀 COMMAND HANDLERS
# ============================================================

def handle_start(chat_id, user_name):
    """Handle /start command - register patient and show welcome."""
    patients = load_patients()
    key = str(chat_id)

    if key not in patients:
        patients[key] = {
            "name": user_name or "صديقي",
            "chat_id": chat_id,
            "registered_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "medications": []
        }
        save_patients(patients)
        welcome = (
            f"🎉 أهلاً وسهلاً <b>{user_name}</b>!\n\n"
            "أنا <b>دكتور بوت</b> 🤖💊\n"
            "مساعدك الشخصي لتذكيرك بأدويتك بالوقت الصحيح!\n\n"
            "📌 <b>شلون أضيف أدويتي؟</b>\n"
            "روح على لوحة التحكم (Dashboard) وأضف أدويتك من هناك،\n"
            "وبعدين أرجع هنا وأنا أذكرك بكل شي! 💪\n\n"
            "⬇️ اختر من القائمة:"
        )
    else:
        patients[key]["name"] = user_name or patients[key].get("name", "صديقي")
        save_patients(patients)
        welcome = (
            f"أهلاً ثاني <b>{user_name}</b>! 😊\n\n"
            "⬇️ اختر من القائمة:"
        )

    bot_stats["active_users"].add(chat_id)
    send_message(chat_id, welcome, reply_markup=main_menu_keyboard())


def handle_reset(chat_id):
    """Clear conversation memory."""
    conversation_history.pop(str(chat_id), None)
    conversation_history.pop(chat_id, None)
    send_message(chat_id, "🔄 تم مسح المحادثة! ابدأ من جديد 😊", reply_markup=main_menu_keyboard())


def handle_menu(chat_id):
    send_message(chat_id, "⬇️ اختر من القائمة:", reply_markup=main_menu_keyboard())


# ============================================================
# 📲 CALLBACK HANDLERS
# ============================================================

def handle_callback(callback):
    """Route all callback_data to the right handler."""
    chat_id    = callback["from"]["id"]
    msg_id     = callback["message"]["message_id"]
    data       = callback["data"]
    cb_id      = callback["id"]
    user_name  = callback["from"].get("first_name", "صديقي")

    answer_callback(cb_id)
    bot_stats["active_users"].add(chat_id)

    patients = load_patients()
    key = str(chat_id)
    meds = patients.get(key, {}).get("medications", [])

    # ── Main Menu ──────────────────────────────────────
    if data == "main_menu":
        edit_message(chat_id, msg_id,
                     f"⬇️ أهلاً <b>{user_name}</b>! اختر من القائمة:",
                     reply_markup=main_menu_keyboard())

    # ── My Medications List ────────────────────────────
    elif data == "my_meds":
        if not meds:
            edit_message(chat_id, msg_id,
                         "💊 ما عندك أدوية مسجلة بعد!\n\n"
                         "📌 افتح لوحة التحكم (Dashboard) وأضف أدويتك من هناك.",
                         reply_markup=back_keyboard())
        else:
            edit_message(chat_id, msg_id,
                         f"💊 <b>أدويتك ({len(meds)} دواء)</b>\nاختر دواء لشوف التفاصيل:",
                         reply_markup=meds_list_keyboard(meds, chat_id, for_taking=False))

    # ── Med Detail ────────────────────────────────────
    elif data.startswith("med_detail_"):
        med_id = data.replace("med_detail_", "")
        med = next((m for m in meds if m["id"] == med_id), None)
        if med:
            card = format_med_card(med, chat_id)
            kb = {
                "inline_keyboard": [
                    [{"text": "✅ سجل أنك أخذته الحين", "callback_data": f"take_{med_id}"}],
                    [{"text": "🔙 رجوع", "callback_data": "my_meds"},
                     {"text": "🏠 القائمة", "callback_data": "main_menu"}],
                ]
            }
            edit_message(chat_id, msg_id, card, reply_markup=kb)

    # ── Take Medication - Show List ───────────────────
    elif data == "take_med":
        if not meds:
            edit_message(chat_id, msg_id,
                         "💊 ما عندك أدوية مسجلة!\nأضفها من لوحة التحكم.",
                         reply_markup=back_keyboard())
        else:
            edit_message(chat_id, msg_id,
                         "✅ <b>سجل أخذ دواء</b>\nاختر الدواء اللي أخذته:",
                         reply_markup=meds_list_keyboard(meds, chat_id, for_taking=True))

    # ── Mark as Taken ─────────────────────────────────
    elif data.startswith("take_"):
        med_id = data.replace("take_", "")
        med = next((m for m in meds if m["id"] == med_id), None)
        if med:
            if is_med_taken_today(chat_id, med_id):
                edit_message(chat_id, msg_id,
                             f"✅ <b>{med['name']}</b>\nسجلت هذا الدواء أخذته اليوم بالفعل! 👍",
                             reply_markup=back_keyboard())
            else:
                mark_med_taken(chat_id, med_id)
                edit_message(chat_id, msg_id,
                             f"✅ <b>تم التسجيل!</b>\n\n"
                             f"💊 <b>{med['name']}</b> - أخذته اليوم ✅\n"
                             f"🕐 {datetime.now().strftime('%H:%M')}\n\n"
                             f"عاش! استمر على انتظامك 💪🌟",
                             reply_markup=back_keyboard())

    # ── Expiry Check ──────────────────────────────────
    elif data == "expiry_check":
        if not meds:
            edit_message(chat_id, msg_id,
                         "ما عندك أدوية مسجلة!", reply_markup=back_keyboard())
            return

        lines = ["⚠️ <b>فحص صلاحية الأدوية</b>\n"]
        for med in meds:
            status, days = get_expiry_status(med.get("expiry", ""))
            if status == "expired":
                lines.append(f"❌ <b>{med['name']}</b> - منتهي منذ {abs(days)} يوم!")
            elif status == "warning":
                lines.append(f"⚠️ <b>{med['name']}</b> - باقي {days} يوم")
            else:
                lines.append(f"✅ {med['name']} - سليم ({days} يوم)")

        edit_message(chat_id, msg_id, "\n".join(lines), reply_markup=back_keyboard())

    # ── Weekly Summary ────────────────────────────────
    elif data == "weekly_summary":
        log = load_taken_log()
        lines = ["📅 <b>ملخص الأسبوع الماضي</b>\n"]
        total_expected = 0
        total_taken = 0

        for i in range(7):
            day = (datetime.now() - timedelta(days=i)).strftime("%Y-%m-%d")
            day_label = (datetime.now() - timedelta(days=i)).strftime("%A %d/%m")
            taken_today = log.get(day, {}).get(key, [])
            expected = len(meds)
            taken_count = len([m for m in meds if m["id"] in taken_today])
            total_expected += expected
            total_taken += taken_count
            pct = int((taken_count / expected * 100)) if expected else 0
            bar = "🟢" if pct >= 80 else ("🟡" if pct >= 50 else "🔴")
            lines.append(f"{bar} {day_label}: {taken_count}/{expected} دواء")

        if total_expected > 0:
            overall = int(total_taken / total_expected * 100)
            lines.append(f"\n📊 <b>نسبة الانتظام: {overall}%</b>")
            if overall >= 80:
                lines.append("🌟 ممتاز! استمر!")
            elif overall >= 50:
                lines.append("💪 كويس، بس لازم تحسن!")
            else:
                lines.append("⚠️ انتبه! الانتظام بالدواء مهم جداً!")

        edit_message(chat_id, msg_id, "\n".join(lines), reply_markup=back_keyboard())

    # ── Ask AI ────────────────────────────────────────
    elif data == "ask_ai":
        edit_message(chat_id, msg_id,
                     "🤖 <b>دكتور بوت جاهز!</b>\n\n"
                     "اكتب سؤالك عن أدويتك أو صحتك وأنا أساعدك 😊\n"
                     "<i>(تذكر: أنا مساعد ذكي وموب بديل عن الطبيب الحقيقي)</i>",
                     reply_markup=back_keyboard())

    # ── Help ──────────────────────────────────────────
    elif data == "help":
        help_text = (
            "ℹ️ <b>مساعدة - دكتور بوت</b>\n\n"
            "📌 <b>كيف أضيف أدويتي؟</b>\n"
            "افتح لوحة التحكم (Dashboard) بالرابط اللي وصلك وأضف أدويتك من هناك.\n\n"
            "📌 <b>الأوامر المتاحة:</b>\n"
            "/start - ابدأ البوت\n"
            "/menu - القائمة الرئيسية\n"
            "/reset - مسح المحادثة\n"
            "/mymeds - شوف أدويتي\n"
            "/taken - سجل أخذ دواء\n\n"
            "📌 <b>التذكيرات:</b>\n"
            "البوت يذكرك بأدويتك بالأوقات اللي حددتها تلقائياً ✅\n\n"
            "📌 <b>التواصل:</b>\n"
            "أي سؤال طبي، اكتب للبوت مباشرة أو راجع طبيبك 🏥"
        )
        edit_message(chat_id, msg_id, help_text, reply_markup=back_keyboard())


# ============================================================
# ⏰ REMINDER SCHEDULER (runs every minute)
# ============================================================

def reminder_loop():
    """Background thread: check every 60 seconds and send due reminders."""
    print("⏰ Reminder scheduler started...")
    while True:
        try:
            now = datetime.now()
            current_time = now.strftime("%H:%M")
            patients = load_patients()

            for key, patient in patients.items():
                chat_id = patient.get("chat_id") or int(key)
                for med in patient.get("medications", []):
                    for t in med.get("times", []):
                        if t == current_time:
                            if not is_med_taken_today(chat_id, med["id"]):
                                send_reminder(chat_id, med)
                                bot_stats["reminders_sent"] += 1

            # Expiry warnings - once daily at 08:00
            if current_time == "08:00":
                for key, patient in patients.items():
                    chat_id = patient.get("chat_id") or int(key)
                    send_expiry_warnings(chat_id, patient.get("medications", []))

            # Weekly summary - every Sunday at 09:00
            if now.weekday() == 6 and current_time == "09:00":
                for key, patient in patients.items():
                    chat_id = patient.get("chat_id") or int(key)
                    send_weekly_summary_msg(chat_id, key, patient.get("medications", []))

            time.sleep(60)

        except Exception as e:
            print(f"[reminder_loop] Error: {e}")
            time.sleep(60)


def send_reminder(chat_id, med):
    """Send a medication reminder with a take/confirm button."""
    status, days = get_expiry_status(med.get("expiry", ""))
    expiry_note = ""
    if status == "warning":
        expiry_note = f"\n⚠️ <b>تنبيه: الدواء ينتهي بعد {days} يوم!</b>"
    elif status == "expired":
        expiry_note = f"\n❌ <b>تحذير: هذا الدواء منتهي الصلاحية! راجع طبيبك!</b>"

    text = (
        f"🔔 <b>وقت دواءك!</b>\n\n"
        f"💊 <b>{med['name']}</b>\n"
        f"📋 الجرعة: {med.get('dosage', '-')}\n"
        f"🕐 {datetime.now().strftime('%H:%M')}"
        f"{expiry_note}\n\n"
        f"هل أخذت دواءك؟ 👇"
    )
    kb = {
        "inline_keyboard": [
            [{"text": "✅ نعم، أخذته!", "callback_data": f"take_{med['id']}"},
             {"text": "⏰ ذكرني بعد 15 دقيقة", "callback_data": f"snooze_{med['id']}"}]
        ]
    }
    send_message(chat_id, text, reply_markup=kb)


def send_expiry_warnings(chat_id, meds):
    """Send daily expiry warnings for any soon-expiring meds."""
    warnings = []
    for med in meds:
        status, days = get_expiry_status(med.get("expiry", ""))
        if status == "warning":
            warnings.append(f"⚠️ <b>{med['name']}</b> - ينتهي بعد {days} يوم")
        elif status == "expired":
            warnings.append(f"❌ <b>{med['name']}</b> - منتهي الصلاحية!")

    if warnings:
        text = "🔔 <b>تنبيه يومي - الصلاحية</b>\n\n" + "\n".join(warnings)
        text += "\n\n⚕️ راجع طبيبك لتجديد الوصفة!"
        send_message(chat_id, text, reply_markup=back_keyboard())


def send_weekly_summary_msg(chat_id, key, meds):
    """Send the weekly summary to a patient."""
    log = load_taken_log()
    lines = ["📅 <b>ملخصك الأسبوعي 🌟</b>\n"]
    total_expected = 0
    total_taken = 0

    for i in range(7):
        day = (datetime.now() - timedelta(days=i)).strftime("%Y-%m-%d")
        taken_today = log.get(day, {}).get(key, [])
        expected = len(meds)
        taken_count = len([m for m in meds if m["id"] in taken_today])
        total_expected += expected
        total_taken += taken_count

    if total_expected > 0:
        overall = int(total_taken / total_expected * 100)
        lines.append(f"📊 <b>نسبة انتظامك هذا الأسبوع: {overall}%</b>")
        if overall >= 80:
            lines.append("🌟 ممتاز! أنت منتظم وهذا يساعد صحتك كثيراً!")
        elif overall >= 50:
            lines.append("💪 كويس، بس حاول تكون أكثر انتظاماً الأسبوع الجاي!")
        else:
            lines.append("⚠️ انتبه! انتظامك بالأدوية ضروري لصحتك. تكدر تراجع طبيبك!")

    send_message(chat_id, "\n".join(lines), reply_markup=main_menu_keyboard())


# ============================================================
# 🔁 MISSED DOSE CHECK (runs at a fixed "end of day" time)
# ============================================================

def missed_dose_check():
    """Runs at 22:00 to notify patients about any meds not taken today."""
    patients = load_patients()
    for key, patient in patients.items():
        chat_id = patient.get("chat_id") or int(key)
        missed = []
        for med in patient.get("medications", []):
            if not is_med_taken_today(chat_id, med["id"]) and med.get("times"):
                missed.append(med["name"])
        if missed:
            text = (
                "😟 <b>تذكير مسائي - أدوية فايتة!</b>\n\n"
                "الأدوية التالية ما أخذتها اليوم:\n"
            )
            for m in missed:
                text += f"❌ {m}\n"
            text += "\n⚕️ استشر طبيبك إذا فاتتك جرعة مهمة."
            send_message(chat_id, text, reply_markup=main_menu_keyboard())


# ============================================================
# 🤖 BOT MAIN POLLING LOOP
# ============================================================

def run_bot():
    """Main Telegram polling loop."""
    print("🤖 Bot polling started...")
    offset = None

    while True:
        try:
            updates = get_updates(offset)

            for update in updates:
                offset = update["update_id"] + 1
                bot_stats["messages_received"] += 1

                # ── Handle callback queries ──────────────
                if "callback_query" in update:
                    cb = update["callback_query"]
                    chat_id = cb["from"]["id"]
                    data = cb.get("data", "")

                    # Snooze: schedule a re-reminder 15 min later
                    if data.startswith("snooze_"):
                        med_id = data.replace("snooze_", "")
                        answer_callback(cb["id"], "⏰ هذكرك بعد 15 دقيقة!")
                        # We spawn a small thread to wait and re-send
                        def snooze_remind(cid, mid):
                            time.sleep(900)   # 15 minutes
                            patients = load_patients()
                            meds = patients.get(str(cid), {}).get("medications", [])
                            med = next((m for m in meds if m["id"] == mid), None)
                            if med and not is_med_taken_today(cid, mid):
                                send_reminder(cid, med)
                        threading.Thread(
                            target=snooze_remind, args=(chat_id, med_id), daemon=True
                        ).start()
                    else:
                        handle_callback(cb)
                    continue

                # ── Handle regular messages ──────────────
                if "message" not in update:
                    continue

                msg      = update["message"]
                chat_id  = msg["chat"]["id"]
                text     = msg.get("text", "")
                user     = msg["from"]
                name     = user.get("first_name", "صديقي")

                bot_stats["active_users"].add(chat_id)

                if not text:
                    continue

                # Commands
                if text.startswith("/start"):
                    handle_start(chat_id, name)
                elif text.startswith("/reset"):
                    handle_reset(chat_id)
                elif text.startswith("/menu"):
                    handle_menu(chat_id)
                elif text.startswith("/mymeds"):
                    patients = load_patients()
                    meds = patients.get(str(chat_id), {}).get("medications", [])
                    if not meds:
                        send_message(chat_id, "💊 ما عندك أدوية مسجلة بعد!\nأضفها من لوحة التحكم.")
                    else:
                        send_message(chat_id, "💊 اختر دواء:", reply_markup=meds_list_keyboard(meds, chat_id))
                elif text.startswith("/taken"):
                    patients = load_patients()
                    meds = patients.get(str(chat_id), {}).get("medications", [])
                    if meds:
                        send_message(chat_id, "✅ أي دواء أخذت؟", reply_markup=meds_list_keyboard(meds, chat_id, for_taking=True))
                    else:
                        send_message(chat_id, "ما عندك أدوية مسجلة!")
                else:
                    # Free-form: send to AI
                    send_typing(chat_id)
                    reply = ask_groq(chat_id, text)
                    send_message(chat_id, reply, reply_markup=main_menu_keyboard())

        except Exception as e:
            print(f"[run_bot] Error: {e}")
            time.sleep(5)


# ============================================================
# 🖥️ GRADIO DASHBOARD
# ============================================================

def dashboard_get_patients():
    """Return a display-friendly list of all patients."""
    patients = load_patients()
    if not patients:
        return "لا يوجد مرضى مسجلون بعد."
    rows = []
    for key, p in patients.items():
        rows.append(f"👤 {p.get('name','?')} | ID: {key} | أدوية: {len(p.get('medications',[]))}")
    return "\n".join(rows)


def add_medication_fn(chat_id_input, med_name, dosage, times_input, expiry, notes):
    """Add a new medication for a patient via the dashboard."""
    try:
        chat_id_input = chat_id_input.strip()
        if not chat_id_input or not med_name.strip():
            return "❌ تأكد من إدخال Chat ID واسم الدواء."

        patients = load_patients()
        key = chat_id_input

        if key not in patients:
            patients[key] = {
                "name": "مريض جديد",
                "chat_id": int(chat_id_input),
                "registered_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                "medications": []
            }

        # Parse times - comma separated
        times = [t.strip() for t in times_input.split(",") if t.strip()]

        # Validate time format
        for t in times:
            try:
                datetime.strptime(t, "%H:%M")
            except ValueError:
                return f"❌ وقت غلط: '{t}'. استخدم صيغة HH:MM مثال: 08:00"

        # Validate expiry
        if expiry:
            try:
                datetime.strptime(expiry, "%Y-%m-%d")
            except ValueError:
                return "❌ تاريخ انتهاء الصلاحية غلط. استخدم YYYY-MM-DD"

        med_id = f"med_{int(time.time())}_{len(patients[key]['medications'])}"
        new_med = {
            "id": med_id,
            "name": med_name.strip(),
            "dosage": dosage.strip(),
            "times": times,
            "expiry": expiry.strip(),
            "notes": notes.strip(),
            "added_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        }

        patients[key]["medications"].append(new_med)
        save_patients(patients)

        # Notify patient on Telegram
        if BOT_TOKEN:
            notif = (
                f"✅ <b>تم إضافة دواء جديد!</b>\n\n"
                f"💊 <b>{med_name}</b>\n"
                f"📋 الجرعة: {dosage}\n"
                f"🕐 أوقات التذكير: {', '.join(times)}\n"
                f"📅 الصلاحية: {expiry}\n\n"
                f"سأذكرك بأوقاتك! 💪"
            )
            send_message(int(chat_id_input), notif, reply_markup=main_menu_keyboard())

        return f"✅ تم إضافة '{med_name}' بنجاح لـ Chat ID: {chat_id_input}"

    except Exception as e:
        return f"❌ خطأ: {str(e)}"


def delete_medication_fn(chat_id_input, med_name_to_delete):
    """Delete a medication by name for a patient."""
    try:
        patients = load_patients()
        key = chat_id_input.strip()
        if key not in patients:
            return "❌ المريض غير موجود."

        before = len(patients[key]["medications"])
        patients[key]["medications"] = [
            m for m in patients[key]["medications"]
            if m["name"].strip().lower() != med_name_to_delete.strip().lower()
        ]
        after = len(patients[key]["medications"])

        if before == after:
            return f"❌ ما لقيت دواء باسم '{med_name_to_delete}'"

        save_patients(patients)
        return f"✅ تم حذف '{med_name_to_delete}' بنجاح!"
    except Exception as e:
        return f"❌ خطأ: {str(e)}"


def view_patient_meds_fn(chat_id_input):
    """View all medications for a patient."""
    try:
        patients = load_patients()
        key = chat_id_input.strip()
        patient = patients.get(key)
        if not patient:
            return "❌ المريض غير موجود."

        meds = patient.get("medications", [])
        if not meds:
            return f"👤 {patient.get('name','?')} - لا توجد أدوية مسجلة."

        lines = [f"👤 المريض: {patient.get('name','?')}\n"]
        for i, med in enumerate(meds, 1):
            status, days = get_expiry_status(med.get("expiry", ""))
            icon = "✅" if status == "ok" else ("⚠️" if status == "warning" else "❌")
            lines.append(
                f"{i}. {icon} {med['name']}\n"
                f"   الجرعة: {med.get('dosage','-')}\n"
                f"   الأوقات: {', '.join(med.get('times',[]))}\n"
                f"   الصلاحية: {med.get('expiry','-')} ({days} يوم)\n"
                f"   ملاحظات: {med.get('notes','-')}\n"
            )
        return "\n".join(lines)
    except Exception as e:
        return f"❌ خطأ: {str(e)}"


def bot_status_fn():
    """Return bot status for dashboard."""
    uptime_start = bot_stats.get("start_time", "غير معروف")
    active_count = len(bot_stats.get("active_users", set()))
    patients_count = len(load_patients())
    return (
        f"🤖 **حالة البوت**\n\n"
        f"✅ البوت يعمل\n"
        f"📨 رسائل مستلمة: {bot_stats['messages_received']}\n"
        f"🔔 تذكيرات أرسلت: {bot_stats['reminders_sent']}\n"
        f"👥 مرضى مسجلون: {patients_count}\n"
        f"🕐 وقت التشغيل: {datetime.now().strftime('%H:%M:%S')}\n"
        f"📅 بدأ منذ: {uptime_start}\n"
    )


def register_patient_fn(chat_id_input, patient_name):
    """Manually register a patient from the dashboard."""
    try:
        chat_id_input = chat_id_input.strip()
        if not chat_id_input:
            return "❌ Chat ID مطلوب."
        patients = load_patients()
        key = chat_id_input
        if key in patients:
            patients[key]["name"] = patient_name.strip() or patients[key]["name"]
            save_patients(patients)
            return f"✅ تم تحديث بيانات المريض: {patient_name}"

        patients[key] = {
            "name": patient_name.strip() or "مريض",
            "chat_id": int(chat_id_input),
            "registered_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "medications": []
        }
        save_patients(patients)

        if BOT_TOKEN:
            send_message(int(chat_id_input),
                         f"🎉 مرحباً <b>{patient_name}</b>!\nتم تسجيلك في نظام تذكير الأدوية ✅\n"
                         f"الآن يمكنك استخدام البوت لإدارة أدويتك!",
                         reply_markup=main_menu_keyboard())

        return f"✅ تم تسجيل المريض: {patient_name} (ID: {chat_id_input})"
    except Exception as e:
        return f"❌ خطأ: {str(e)}"


# ============================================================
# 🎨 BUILD GRADIO UI
# ============================================================

def build_dashboard():
    with gr.Blocks(
        title="💊 دكتور بوت - لوحة التحكم",
        theme=gr.themes.Soft(primary_hue="blue", secondary_hue="green"),
        css="""
        .rtl { direction: rtl; text-align: right; }
        .title-box { text-align: center; padding: 10px; }
        footer { display: none !important; }
        """
    ) as demo:

        # ── Header ────────────────────────────────────────
        gr.HTML("""
        <div style="text-align:center; padding:20px; background:linear-gradient(135deg,#1a73e8,#0d47a1); border-radius:12px; color:white; margin-bottom:20px;">
            <h1 style="margin:0; font-size:2em;">💊 دكتور بوت</h1>
            <p style="margin:5px 0; font-size:1.1em; opacity:0.9;">نظام تذكير الأدوية الذكي - لوحة التحكم</p>
            <p style="margin:0; font-size:0.85em; opacity:0.7;">Medication Reminder Bot Dashboard</p>
        </div>
        """)

        # ── How to get Chat ID ────────────────────────────
        gr.HTML("""
        <div style="background:#e8f5e9; border-right:4px solid #4caf50; padding:12px; border-radius:8px; margin-bottom:15px; direction:rtl;">
            <b>📌 كيف أعرف Chat ID الخاص بي؟</b><br>
            1. افتح تيليغرام وابحث عن <b>@userinfobot</b><br>
            2. اكتب له /start<br>
            3. سيعطيك Chat ID الخاص بك<br>
            4. ألصق الرقم هنا في الحقول أدناه ✅
        </div>
        """)

        with gr.Tabs():

            # ── Tab 1: Bot Status ─────────────────────────
            with gr.Tab("📊 حالة البوت"):
                status_out = gr.Markdown(value=bot_status_fn())
                patients_out = gr.Textbox(
                    label="👥 المرضى المسجلون",
                    value=dashboard_get_patients(),
                    lines=8,
                    interactive=False,
                    elem_classes="rtl"
                )
                refresh_btn = gr.Button("🔄 تحديث", variant="primary")
                refresh_btn.click(
                    fn=lambda: (bot_status_fn(), dashboard_get_patients()),
                    outputs=[status_out, patients_out]
                )

            # ── Tab 2: Register Patient ───────────────────
            with gr.Tab("👤 تسجيل مريض"):
                gr.HTML('<div style="direction:rtl; font-weight:bold; margin-bottom:10px;">أدخل بيانات المريض:</div>')
                reg_chat_id   = gr.Textbox(label="Chat ID (من @userinfobot)", placeholder="مثال: 123456789")
                reg_name      = gr.Textbox(label="اسم المريض", placeholder="مثال: أحمد علي")
                reg_btn       = gr.Button("✅ تسجيل المريض", variant="primary")
                reg_out       = gr.Textbox(label="النتيجة", interactive=False)
                reg_btn.click(fn=register_patient_fn, inputs=[reg_chat_id, reg_name], outputs=reg_out)

            # ── Tab 3: Add Medication ─────────────────────
            with gr.Tab("💊 إضافة دواء"):
                gr.HTML('<div style="direction:rtl; font-weight:bold; margin-bottom:10px;">أضف دواءً جديداً للمريض:</div>')

                with gr.Row():
                    add_chat_id = gr.Textbox(label="Chat ID المريض", placeholder="123456789")
                    add_name    = gr.Textbox(label="اسم الدواء *", placeholder="مثال: أموكسيسيلين")

                with gr.Row():
                    add_dosage  = gr.Textbox(label="الجرعة", placeholder="مثال: حبة واحدة")
                    add_expiry  = gr.Textbox(label="تاريخ انتهاء الصلاحية (YYYY-MM-DD)", placeholder="2025-12-31")

                add_times   = gr.Textbox(
                    label="أوقات التذكير (مفصولة بفاصلة - HH:MM)",
                    placeholder="مثال: 08:00, 14:00, 21:00"
                )
                add_notes   = gr.Textbox(label="ملاحظات (اختياري)", placeholder="مثال: يؤخذ بعد الأكل")
                add_btn     = gr.Button("➕ إضافة الدواء", variant="primary")
                add_out     = gr.Textbox(label="النتيجة", interactive=False)
                add_btn.click(
                    fn=add_medication_fn,
                    inputs=[add_chat_id, add_name, add_dosage, add_times, add_expiry, add_notes],
                    outputs=add_out
                )

            # ── Tab 4: View Patient Meds ──────────────────
            with gr.Tab("📋 عرض الأدوية"):
                gr.HTML('<div style="direction:rtl; font-weight:bold; margin-bottom:10px;">اعرض أدوية مريض:</div>')
                view_chat_id = gr.Textbox(label="Chat ID المريض", placeholder="123456789")
                view_btn     = gr.Button("🔍 عرض", variant="primary")
                view_out     = gr.Textbox(label="الأدوية", lines=15, interactive=False, elem_classes="rtl")
                view_btn.click(fn=view_patient_meds_fn, inputs=[view_chat_id], outputs=view_out)

            # ── Tab 5: Delete Medication ──────────────────
            with gr.Tab("🗑️ حذف دواء"):
                gr.HTML('<div style="direction:rtl; font-weight:bold; margin-bottom:10px;">حذف دواء من قائمة مريض:</div>')
                del_chat_id  = gr.Textbox(label="Chat ID المريض", placeholder="123456789")
                del_med_name = gr.Textbox(label="اسم الدواء المراد حذفه", placeholder="مثال: أموكسيسيلين")
                del_btn      = gr.Button("🗑️ حذف", variant="stop")
                del_out      = gr.Textbox(label="النتيجة", interactive=False)
                del_btn.click(fn=delete_medication_fn, inputs=[del_chat_id, del_med_name], outputs=del_out)

            # ── Tab 6: Guide ──────────────────────────────
            with gr.Tab("📖 دليل الاستخدام"):
                gr.Markdown("""
## 📖 دليل الاستخدام - دكتور بوت

---

### 🚀 خطوات البدء

1. **ابدأ مع البوت على تيليغرام**
   - ابحث عن البوت وافتحه
   - اكتب `/start`

2. **احصل على Chat ID**
   - ابحث عن `@userinfobot` في تيليغرام
   - اكتب `/start` وستحصل على رقمك

3. **سجل نفسك من هنا**
   - روح لتبويب "تسجيل مريض"
   - أدخل Chat ID واسمك

4. **أضف أدويتك**
   - روح لتبويب "إضافة دواء"
   - أضف كل دواء مع وقته وصلاحيته

---

### ⏰ نظام التذكير

| النوع | الوقت |
|-------|-------|
| تذكير الدواء | حسب الأوقات اللي حددتها |
| تحذير الصلاحية | كل يوم الساعة 8 صباحاً |
| تنبيه فوات الجرعة | الساعة 10 مساءً |
| ملخص أسبوعي | كل أحد الساعة 9 صباحاً |

---

### 📱 أوامر البوت

| الأمر | الوظيفة |
|-------|---------|
| `/start` | ابدأ البوت |
| `/menu` | القائمة الرئيسية |
| `/mymeds` | عرض أدويتي |
| `/taken` | سجل أخذ دواء |
| `/reset` | مسح المحادثة |

---

### ⚠️ ملاحظة مهمة

هذا البوت مساعد تذكير فقط وليس بديلاً عن الطبيب.
دائماً استشر طبيبك للحصول على المشورة الطبية المناسبة. 🏥
                """)

        gr.HTML("""
        <div style="text-align:center; padding:15px; color:#666; font-size:0.85em; margin-top:20px;">
            💊 دكتور بوت - نظام تذكير الأدوية الذكي | Medication Reminder Bot<br>
            مبني بـ Python + Telegram Bot API + Groq AI + Gradio
        </div>
        """)

    return demo


# ============================================================
# ⏰ MISSED DOSE SCHEDULER THREAD
# ============================================================

def missed_dose_scheduler():
    """Check at 22:00 each night for missed doses."""
    while True:
        try:
            now = datetime.now()
            if now.strftime("%H:%M") == "22:00":
                missed_dose_check()
                time.sleep(61)   # avoid double trigger
            time.sleep(30)
        except Exception as e:
            print(f"[missed_dose_scheduler] Error: {e}")
            time.sleep(60)


# ============================================================
# 🏁 MAIN ENTRY POINT
# ============================================================

if __name__ == "__main__":
    print("=" * 50)
    print("💊 دكتور بوت - Medication Reminder Bot")
    print("=" * 50)

    if not BOT_TOKEN:
        print("⚠️  BOT_TOKEN غير محدد! البوت لن يعمل بدون توكن.")
    else:
        print("✅ BOT_TOKEN موجود")

    if not GROQ_API_KEY:
        print("⚠️  GROQ_API_KEY غير محدد! الذكاء الاصطناعي معطل.")
    else:
        print("✅ GROQ_API_KEY موجود")

    # Start Telegram polling bot in background thread
    bot_thread = threading.Thread(target=run_bot, daemon=True)
    bot_thread.start()
    print("🤖 Bot thread started")

    # Start reminder scheduler in background thread
    reminder_thread = threading.Thread(target=reminder_loop, daemon=True)
    reminder_thread.start()
    print("⏰ Reminder scheduler started")

    # Start missed dose scheduler
    missed_thread = threading.Thread(target=missed_dose_scheduler, daemon=True)
    missed_thread.start()
    print("😟 Missed dose scheduler started")

    # Launch Gradio dashboard
    print("🖥️  Starting Gradio dashboard...")
    demo = build_dashboard()
    demo.launch(
        server_name="0.0.0.0",
        server_port=7860,
        show_error=True,
    )
