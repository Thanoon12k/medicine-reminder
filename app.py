# ╔══════════════════════════════════════════════════════════════╗
# ║       💊 دكتور بوت v3 — AI Medication Reminder Bot          ║
# ║   كل شي من البوت، ذكاء اصطناعي، بدون داشبورد               ║
# ║   Multi-patient · Conversational Onboarding · Groq AI        ║
# ╚══════════════════════════════════════════════════════════════╝

import json
import threading
import requests
import time
import os
import logging
from datetime import datetime, timedelta, timezone

IRQ_TZ = timezone(timedelta(hours=3))

def now_iraq():
    return datetime.now(IRQ_TZ)

# ============================================================
# 📋 LOGGING
# ============================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("bot.log", encoding="utf-8"),
    ],
)
log = logging.getLogger("DoctorBot")

# ============================================================
# 🔐 ENV VARIABLES
# ============================================================
from dotenv import load_dotenv
load_dotenv()

BOT_TOKEN    = os.environ.get("BOT_TOKEN", "").strip(' \'"')
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "").strip(' \'"')
BASE_URL     = f"https://api.telegram.org/bot{BOT_TOKEN}"

# ============================================================
# 📁 FILES
# ============================================================
USERS_FILE   = "users.json"      # كل المستخدمين وبياناتهم
TAKEN_FILE   = "taken.json"      # سجل الجرعات

# ============================================================
# 📊 RUNTIME STATE
# ============================================================
bot_stats = {
    "messages": 0,
    "reminders_sent": 0,
    "start_time": now_iraq().strftime("%Y-%m-%d %H:%M:%S"),
}

# حالة المحادثة لكل مستخدم — لتتبع مرحلة الإدخال
# user_state[chat_id] = {
#   "step": "idle" | "await_patient_name" | "await_meds" | "await_times" | "await_expiry" | "await_more",
#   "pending_patient": { name, meds_raw, times_raw },
#   "editing_patient": "اسم المريض"
# }
user_state = {}

# ذاكرة المحادثة للـ AI
conversation_memory = {}   # chat_id -> [ {role, content}, ... ]

# ============================================================
# 💾 DATABASE HELPERS
# ============================================================

def load_users():
    try:
        if os.path.exists(USERS_FILE):
            with open(USERS_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception as e:
        log.error(f"[load_users] {e}")
    return {}


def save_users(data):
    try:
        with open(USERS_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        log.error(f"[save_users] {e}")


def load_taken():
    try:
        if os.path.exists(TAKEN_FILE):
            with open(TAKEN_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
    except Exception as e:
        log.error(f"[load_taken] {e}")
    return {}


def save_taken(data):
    try:
        with open(TAKEN_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        log.error(f"[save_taken] {e}")


def today():
    return now_iraq().strftime("%Y-%m-%d")


def is_taken(chat_id, patient_name, med_id, time_str=None):
    log_ = load_taken()
    key  = f"{chat_id}:{patient_name}"
    taken_list = log_.get(today(), {}).get(key, [])
    if time_str:
        return f"{med_id}|{time_str}" in taken_list
    else:
        return any(x.startswith(med_id) for x in taken_list) or med_id in taken_list


def is_skipped(chat_id, patient_name, med_id, time_str):
    log_ = load_taken()
    key  = f"{chat_id}:{patient_name}"
    taken_list = log_.get(today(), {}).get(key, [])
    return f"skip_{med_id}|{time_str}" in taken_list


def mark_taken(chat_id, patient_name, med_id, time_str=None):
    log_ = load_taken()
    t    = today()
    key  = f"{chat_id}:{patient_name}"
    if t not in log_:
        log_[t] = {}
    if key not in log_[t]:
        log_[t][key] = []
    val = f"{med_id}|{time_str}" if time_str else med_id
    if val not in log_[t][key]:
        log_[t][key].append(val)
    save_taken(log_)


def mark_skipped(chat_id, patient_name, med_id, time_str):
    log_ = load_taken()
    t    = today()
    key  = f"{chat_id}:{patient_name}"
    if t not in log_:
        log_[t] = {}
    if key not in log_[t]:
        log_[t][key] = []
    val = f"skip_{med_id}|{time_str}"
    if val not in log_[t][key]:
        log_[t][key].append(val)
    save_taken(log_)


def get_user(chat_id):
    users = load_users()
    return users.get(str(chat_id))


def get_patients(chat_id):
    u = get_user(chat_id)
    if not u:
        return {}
    return u.get("patients", {})


def expiry_info(exp_str):
    """Returns (status, days_remaining)  status: ok / warning / expired / unknown"""
    try:
        exp = datetime.strptime(exp_str, "%Y-%m-%d")
        diff = (exp - now_iraq()).days
        if diff < 0:   return "expired", diff
        if diff <= 30: return "warning", diff
        return "ok", diff
    except Exception:
        return "unknown", 0

# ============================================================
# 📱 TELEGRAM HELPERS
# ============================================================

def tg(method, payload=None, timeout=15):
    try:
        r = requests.post(f"{BASE_URL}/{method}", json=payload or {}, timeout=timeout)
        res = r.json()
        if not res.get("ok"):
            log.error(f"[tg/{method}] Error from Telegram: {res}")
        return res
    except Exception as e:
        log.error(f"[tg/{method}] Exception: {e}")
        return {}


def send(chat_id, text, kb=None, parse_mode="HTML"):
    payload = {"chat_id": chat_id, "text": text, "parse_mode": parse_mode}
    if kb:
        payload["reply_markup"] = kb
    return tg("sendMessage", payload)


def edit(chat_id, msg_id, text, kb=None):
    payload = {"chat_id": chat_id, "message_id": msg_id, "text": text, "parse_mode": "HTML"}
    if kb:
        payload["reply_markup"] = kb
    tg("editMessageText", payload)


def typing(chat_id):
    tg("sendChatAction", {"chat_id": chat_id, "action": "typing"})


def ack(cb_id, text="✅"):
    tg("answerCallbackQuery", {"callback_query_id": cb_id, "text": text})


def get_updates(offset=None):
    params = {"timeout": 8, "allowed_updates": ["message", "callback_query"]}
    if offset:
        params["offset"] = offset
    try:
        r = requests.get(f"{BASE_URL}/getUpdates", params=params, timeout=12)
        res = r.json()
        if not res.get("ok"):
            error_code = res.get("error_code", 0)
            if error_code == 409:
                # Another instance is running — wait and let it die
                log.warning("[get_updates] 409 Conflict: another bot instance detected, waiting 5s...")
                time.sleep(5)
            else:
                log.error(f"[get_updates] Error from Telegram: {res}")
        return res.get("result", [])
    except requests.exceptions.Timeout:
        return []
    except Exception as e:
        if "timed out" not in str(e).lower():
            log.error(f"[get_updates] Exception: {e}")
        return []

# ============================================================
# ⌨️ KEYBOARD BUILDERS
# ============================================================

def kb_main_menu(has_patients=False):
    rows = [
        [{"text": "➕ إضافة مريض جديد",      "callback_data": "add_patient"}],
    ]
    if has_patients:
        rows.append([{"text": "👥 مرضاي",        "callback_data": "list_patients"}])
        rows.append([{"text": "💊 أدوية اليوم",  "callback_data": "today_meds"}])
        rows.append([{"text": "📅 ملخص الأسبوع", "callback_data": "weekly"}])
    rows.append([{"text": "ℹ️ مساعدة",          "callback_data": "help"}])
    return {"inline_keyboard": rows}


def kb_patients_list(patients, action_prefix):
    """List all patient names as buttons."""
    rows = []
    for pname in patients:
        rows.append([{"text": f"👤 {pname}", "callback_data": f"{action_prefix}{pname}"}])
    rows.append([{"text": "🏠 القائمة الرئيسية", "callback_data": "main_menu"}])
    return {"inline_keyboard": rows}


def kb_patient_detail(pname):
    return {"inline_keyboard": [
        [{"text": "💊 أدويته اليوم",        "callback_data": f"pt_today_{pname}"}],
        [{"text": "➕ أضف دواء له",          "callback_data": f"pt_addmed_{pname}"}],
        [{"text": "✏️ عدّل دواء",            "callback_data": f"pt_editmeds_{pname}"}],
        [{"text": "🗑️ احذف هذا المريض",     "callback_data": f"pt_del_confirm_{pname}"}],
        [{"text": "🔙 رجوع للمرضى",         "callback_data": "list_patients"}],
    ]}


def kb_back_main():
    return {"inline_keyboard": [[{"text": "🏠 القائمة الرئيسية", "callback_data": "main_menu"}]]}


def kb_back_patients():
    return {"inline_keyboard": [[{"text": "🔙 رجوع للمرضى", "callback_data": "list_patients"}]]}


def kb_taken(chat_id, pname, med_id, med_name, time_str):
    taken = is_taken(chat_id, pname, med_id, time_str)
    if taken:
        return {"inline_keyboard": [
            [{"text": f"✅ تم إعطاء {med_name}",  "callback_data": "already_taken"}],
            [{"text": "🏠 القائمة",               "callback_data": "main_menu"}],
        ]}
    return {"inline_keyboard": [
        [{"text": f"✅ أخذ الجرعة ({time_str})",
          "callback_data": f"mark_{pname}|{med_id}|{time_str}|{med_name}"}],
        [{"text": "❌ ترك الجرعة",
          "callback_data": f"skip_{pname}|{med_id}|{time_str}|{med_name}"}],
        [{"text": "⏰ ذكرني بعد 10 دقائق",
          "callback_data": f"snooze_{pname}|{med_id}|{time_str}|{med_name}"}],
    ]}


def kb_meds_edit_list(meds, pname):
    rows = []
    for m in meds:
        rows.append([{"text": f"✏️ {m['name']}", "callback_data": f"editmed_{pname}|{m['id']}"}])
    rows.append([{"text": "🔙 رجوع",            "callback_data": f"patient_{pname}"}])
    return {"inline_keyboard": rows}


def kb_edit_field(pname, med_id):
    return {"inline_keyboard": [
        [{"text": "📝 اسم الدواء",      "callback_data": f"edf_name_{pname}|{med_id}"},
         {"text": "💊 الجرعة",          "callback_data": f"edf_dosage_{pname}|{med_id}"}],
        [{"text": "🕐 الأوقات",         "callback_data": f"edf_times_{pname}|{med_id}"},
         {"text": "📅 الصلاحية",        "callback_data": f"edf_expiry_{pname}|{med_id}"}],
        [{"text": "🗑️ احذف هذا الدواء","callback_data": f"delmed_{pname}|{med_id}"}],
        [{"text": "🔙 رجوع",            "callback_data": f"pt_editmeds_{pname}"}],
    ]}

# ============================================================
# 🤖 GROQ AI — المساعد الطبي
# ============================================================

AI_SYSTEM = """
أنت "دكتور بوت" — مساعد ذكي لتذكير الأدوية.
تتكلم بالعربي العراقي البسيط والواضح.
ردودك قصيرة ومفيدة وودودة مع إيموجي مناسبة.
أنت موب بديل عن الطبيب — إذا السؤال خطير قول للمستخدم يراجع الطبيب فوراً.
ساعد بأسئلة الأدوية البسيطة والتوقيتات والجرعات العامة.
إذا سألك أحد عن ميزات البوت أو كيف يضيف مريض، شرح له بخطوات واضحة.
"""

def ask_ai(chat_id, message, system_extra=""):
    """Send message to Groq and get Iraqi Arabic response."""
    try:
        if not GROQ_API_KEY:
            return "خدمة الذكاء الاصطناعي مو مفعّلة، بس أقدر أساعدك بالقوائم! 😊"

        cid = str(chat_id)
        if cid not in conversation_memory:
            conversation_memory[cid] = []

        conversation_memory[cid].append({"role": "user", "content": message})
        # Keep last 16 turns
        if len(conversation_memory[cid]) > 32:
            conversation_memory[cid] = conversation_memory[cid][-32:]

        system = AI_SYSTEM + ("\n" + system_extra if system_extra else "")

        resp = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {GROQ_API_KEY}",
                     "Content-Type": "application/json"},
            json={
                "model": "llama-3.3-70b-versatile",
                "messages": [{"role": "system", "content": system}]
                             + conversation_memory[cid],
                "max_tokens": 400,
                "temperature": 0.7,
            },
            timeout=15,
        )
        reply = resp.json()["choices"][0]["message"]["content"].strip()
        conversation_memory[cid].append({"role": "assistant", "content": reply})
        return reply

    except Exception as e:
        log.error(f"[ask_ai] {e}")
        return "معذرة، صارت مشكلة تقنية بسيطة 😅 حاول مرة ثانية!"


def ai_parse_meds(raw_text):
    """
    Use AI to extract structured medication list from free-form text.
    Returns JSON string like:
    [{"name":"...", "dosage":"...", "times":["08:00","20:00"], "expiry":"2025-12-31", "notes":"..."}]
    """
    if not GROQ_API_KEY:
        return None

    prompt = f"""
المستخدم كتب هذا النص عن الأدوية:
\"\"\"{raw_text}\"\"\"

استخرج منه قائمة الأدوية وأرجعها بصيغة JSON فقط، بدون أي كلام إضافي أو ```json.
الصيغة المطلوبة:
[
  {{
    "name": "اسم الدواء",
    "dosage": "الجرعة",
    "times": ["HH:MM", "HH:MM"],
    "expiry": "YYYY-MM-DD أو فارغ إذا ما ذُكر",
    "notes": "ملاحظات إضافية إذا وجدت"
  }}
]

قواعد:
- إذا ذُكر وقت كـ "الصبح" حوّله لـ 08:00، "الظهر" لـ 14:00، "العصر" لـ 16:00، "المساء/المغرب" لـ 19:00، "النوم/الليل" لـ 21:00
- إذا كُتب "مرتين" أضف وقتين مناسبين مثل 08:00 و20:00
- إذا كُتب "ثلاث مرات" أضف 08:00، 14:00، 20:00
- الصلاحية إذا ما ذُكرت اتركها فارغة ""
- أرجع JSON فقط
"""
    try:
        resp = requests.post(
            "https://api.groq.com/openai/v1/chat/completions",
            headers={"Authorization": f"Bearer {GROQ_API_KEY}",
                     "Content-Type": "application/json"},
            json={
                "model": "llama-3.3-70b-versatile",
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": 800,
                "temperature": 0.1,
            },
            timeout=20,
        )
        raw = resp.json()["choices"][0]["message"]["content"].strip()
        # Strip accidental code fences
        raw = raw.replace("```json", "").replace("```", "").strip()
        parsed = json.loads(raw)
        return parsed
    except Exception as e:
        log.error(f"[ai_parse_meds] {e}")
        return None

# ============================================================
# 🧩 ONBOARDING FLOW — STATE MACHINE
# ============================================================
# Steps:
#   idle              → normal use
#   await_patient_name → waiting for patient name
#   await_meds         → waiting for medication description
#   await_expiry       → waiting for expiry dates (optional)
#   await_add_more     → ask if they want to add another patient
#   edit_field         → waiting for new value of a field
# ============================================================

def state(chat_id):
    return user_state.get(str(chat_id), {})


def set_state(chat_id, **kwargs):
    cid = str(chat_id)
    if cid not in user_state:
        user_state[cid] = {"step": "idle"}
    user_state[cid].update(kwargs)


def clear_state(chat_id):
    user_state.pop(str(chat_id), None)

# ============================================================
# 💬 ONBOARDING MESSAGES
# ============================================================

WELCOME_NEW = """
🎉 أهلاً وسهلاً بيك في <b>دكتور بوت</b>! 💊🤖

أنا مساعدك الشخصي لتذكيرك وتذكير أهلك بمواعيد الأدوية. 

✨ <b>شلون أشتغل؟</b>
• تقدر تسجل أكثر من مريض (أبوك، أمك، جدك…)
• لكل مريض أدويته وأوقاته
• أذكرك كل وقت دواء ولازم تأكد تعطيه إياه
• أرسلك تنبيهات انتهاء الصلاحية

⬇️ ابدأ بإضافة أول مريض!
"""

WELCOME_BACK = "أهلاً ثاني! 😊 شبيك؟ اختر من القائمة:"

MSG_ASK_PATIENT_NAME = """
👤 <b>إضافة مريض جديد</b>

شكتب اسم المريض؟
<i>(مثال: أبو علي، ماما، جدي)</i>
"""

MSG_ASK_MEDS = """
💊 <b>شلون تكتب الأدوية؟</b>

اكتبلي كل الأدوية بأسلوب طبيعي، مثلاً:

<code>أموكسيسيلين حبة كل 8 ساعات
ميتفورمين 500 ملغ بعد الأكل مرتين يومياً
ومبيزول قبل النوم</code>

أو بطريقة أبسط:
<code>فيتامين د مرة الصبح، ضغط حبتين الصبح والمساء</code>

الذكاء الاصطناعي يفهم أي أسلوب تكتبه 🤖✨
"""

MSG_PROCESSING = "⏳ جاري معالجة الأدوية بالذكاء الاصطناعي..."

# ============================================================
# 🚀 COMMAND HANDLERS
# ============================================================

def handle_start(chat_id, user_name):
    users = load_users()
    cid   = str(chat_id)

    if cid not in users:
        # مستخدم جديد
        users[cid] = {
            "name":       user_name or "صديقي",
            "chat_id":    chat_id,
            "joined_at":  now_iraq().strftime("%Y-%m-%d %H:%M:%S"),
            "patients":   {}
        }
        save_users(users)
        send(chat_id, WELCOME_NEW,
             kb={"inline_keyboard": [
                 [{"text": "➕ أضف أول مريض الحين!", "callback_data": "add_patient"}]
             ]})
    else:
        # مستخدم موجود
        users[cid]["name"] = user_name or users[cid].get("name", "صديقي")
        save_users(users)
        patients = users[cid].get("patients", {})
        send(chat_id, WELCOME_BACK, kb=kb_main_menu(bool(patients)))


def handle_reset(chat_id):
    clear_state(chat_id)
    conversation_memory.pop(str(chat_id), None)
    send(chat_id, "🔄 تم مسح المحادثة والحالة! ابدأ من جديد 😊",
         kb=kb_main_menu(bool(get_patients(chat_id))))


def handle_menu(chat_id):
    clear_state(chat_id)
    send(chat_id, "⬇️ اختر من القائمة:",
         kb=kb_main_menu(bool(get_patients(chat_id))))

# ============================================================
# ➕ ADD PATIENT FLOW
# ============================================================

def flow_add_patient_start(chat_id):
    set_state(chat_id, step="await_patient_name")
    send(chat_id, MSG_ASK_PATIENT_NAME)


def flow_got_patient_name(chat_id, name):
    name = name.strip()
    if not name or len(name) < 2:
        send(chat_id, "❌ الاسم قصير جداً، حاول ثاني:")
        return

    # Check duplicate
    patients = get_patients(chat_id)
    if name in patients:
        send(chat_id, f"⚠️ عندك مريض بنفس الاسم «{name}» بالفعل!\n\nجرب اسم مختلف أو أضف ملاحظة مثل «أبو علي - بصرة»:")
        return

    set_state(chat_id, step="await_meds", pending_name=name)
    send(chat_id, f"✅ تمام! المريض: <b>{name}</b>\n\n{MSG_ASK_MEDS}")


def flow_got_meds_text(chat_id, raw_text):
    st = state(chat_id)
    pname = st.get("pending_name", "")

    # Show processing message
    msg = send(chat_id, MSG_PROCESSING)
    msg_id = msg.get("result", {}).get("message_id")

    # Parse with AI
    meds = ai_parse_meds(raw_text)

    if not meds:
        # AI failed — manual fallback
        if msg_id:
            edit(chat_id, msg_id,
                 "⚠️ ما قدرت أفهم الأدوية بشكل كامل.\n\n"
                 "حاول تكتبها بشكل أوضح، مثلاً:\n"
                 "<code>اسم الدواء - الجرعة - عدد المرات في اليوم</code>")
        return

    # Save meds to user
    users   = load_users()
    cid     = str(chat_id)
    med_ids = {}

    for m in meds:
        med_id = f"med_{int(time.time())}_{len(med_ids)}"
        med_ids[med_id] = {
            "id":     med_id,
            "name":   m.get("name",   "دواء"),
            "dosage": m.get("dosage", ""),
            "times":  m.get("times",  []),
            "expiry": m.get("expiry", ""),
            "notes":  m.get("notes",  ""),
            "added":  now_iraq().strftime("%Y-%m-%d %H:%M:%S"),
        }
        time.sleep(0.01)  # ensure unique timestamps

    if cid not in users:
        users[cid] = {"patients": {}}
    if "patients" not in users[cid]:
        users[cid]["patients"] = {}
    if pname not in users[cid]["patients"]:
        # New patient
        users[cid]["patients"][pname] = {
            "name":  pname,
            "meds":  {},
            "added": now_iraq().strftime("%Y-%m-%d %H:%M:%S"),
        }
    # Merge new meds into existing ones (don't overwrite!)
    existing_meds = users[cid]["patients"][pname].setdefault("meds", {})
    existing_meds.update(med_ids)
    save_users(users)

    # Build confirmation message
    lines = [f"✅ <b>تم حفظ المريض {pname}!</b>\n\n💊 <b>الأدوية المسجلة:</b>"]
    for m in med_ids.values():
        times_str = "، ".join(m["times"]) if m["times"] else "لم تحدد"
        exp_str   = m["expiry"] if m["expiry"] else "لم تحدد"
        lines.append(
            f"\n• <b>{m['name']}</b>"
            + (f"\n  📋 الجرعة: {m['dosage']}" if m["dosage"] else "")
            + f"\n  🕐 الأوقات: {times_str}"
            + f"\n  📅 الصلاحية: {exp_str}"
            + (f"\n  📝 {m['notes']}" if m["notes"] else "")
        )

    lines.append("\n\nهل أوقات التنبيه هذه مناسبة أم تحتاج لتعديل؟")

    clear_state(chat_id)

    kb_after_add = {"inline_keyboard": [
        [{"text": "✅ نعم، الأوقات مناسبة (للرئيسية)", "callback_data": "main_menu"}],
        [{"text": "✏️ لا، أريد تعديل الأوقات", "callback_data": f"pt_editmeds_{pname}"}],
        [{"text": "➕ إضافة مريض ثاني", "callback_data": "add_patient"}],
    ]}

    # Edit the processing message to show result
    if msg_id:
        edit(chat_id, msg_id, "\n".join(lines), kb=kb_after_add)
    else:
        send(chat_id, "\n".join(lines), kb=kb_after_add)

# ============================================================
# ➕ ADD MED TO EXISTING PATIENT
# ============================================================

def flow_add_med_start(chat_id, pname):
    set_state(chat_id, step="await_meds_for_patient", pending_name=pname)
    send(chat_id,
         f"💊 <b>إضافة دواء جديد لـ {pname}</b>\n\n{MSG_ASK_MEDS}")


# ============================================================
# ✏️ EDIT FIELD FLOW
# ============================================================

def flow_edit_field_start(chat_id, pname, med_id, field):
    labels = {
        "name":   "اسم الدواء الجديد",
        "dosage": "الجرعة الجديدة",
        "times":  "الأوقات الجديدة (مفصولة بفاصلة مثل: 08:00, 20:00)",
        "expiry": "تاريخ الصلاحية الجديد (YYYY-MM-DD)",
        "notes":  "الملاحظات الجديدة",
    }
    set_state(chat_id,
              step="await_edit_value",
              edit_pname=pname,
              edit_med_id=med_id,
              edit_field=field)
    send(chat_id, f"✏️ اكتب <b>{labels.get(field, field)}</b>:")


def flow_got_edit_value(chat_id, new_value):
    st     = state(chat_id)
    pname  = st.get("edit_pname")
    med_id = st.get("edit_med_id")
    field  = st.get("edit_field")

    if not all([pname, med_id, field]):
        clear_state(chat_id)
        send(chat_id, "❌ حدث خطأ. ارجع للقائمة.", kb=kb_back_main())
        return

    users = load_users()
    cid   = str(chat_id)
    med   = users.get(cid, {}).get("patients", {}).get(pname, {}).get("meds", {}).get(med_id)

    if not med:
        clear_state(chat_id)
        send(chat_id, "❌ الدواء مو موجود.", kb=kb_back_main())
        return

    # Parse value
    if field == "times":
        val = [t.strip() for t in new_value.replace("،", ",").split(",") if t.strip()]
    else:
        val = new_value.strip()

    users[cid]["patients"][pname]["meds"][med_id][field] = val
    save_users(users)
    clear_state(chat_id)

    send(chat_id,
         f"✅ تم تحديث <b>{field}</b> للدواء <b>{med['name']}</b> بنجاح!",
         kb=kb_patient_detail(pname))

# ============================================================
# 📋 VIEW HELPERS
# ============================================================

def fmt_patient_meds(chat_id, pname, patients):
    p    = patients.get(pname, {})
    meds = p.get("meds", {})

    if not meds:
        return f"💊 المريض <b>{pname}</b> ما عنده أدوية مسجلة بعد."

    lines = [f"💊 <b>أدوية {pname}:</b>\n"]
    for m in meds.values():
        taken     = is_taken(chat_id, pname, m["id"])
        status, d = expiry_info(m.get("expiry", ""))
        t_icon    = "✅" if taken else "⏳"
        e_icon    = {"ok": "📅", "warning": "⚠️", "expired": "❌"}.get(status, "📅")
        times_str = "، ".join(m.get("times", [])) or "لم تحدد"

        lines.append(
            f"\n{t_icon} <b>{m['name']}</b>"
            + (f"\n  📋 {m['dosage']}" if m.get("dosage") else "")
            + f"\n  🕐 {times_str}"
            + (f"\n  {e_icon} الصلاحية: {m['expiry']}"
               + (f" (⚠️ باقي {d} يوم!)" if status == "warning" else
                  f" (❌ منتهي منذ {abs(d)} يوم!)" if status == "expired" else "")
               if m.get("expiry") else "")
            + (f"\n  📝 {m['notes']}" if m.get("notes") else "")
        )
    return "\n".join(lines)


def fmt_today_all(chat_id, patients):
    """All meds for all patients due today."""
    if not patients:
        return "👥 ما عندك مرضى مسجلين بعد."

    lines = [f"🌅 <b>أدوية اليوم — {today()}</b>\n"]
    for pname, p in patients.items():
        meds = p.get("meds", {})
        if not meds:
            continue
        lines.append(f"\n👤 <b>{pname}:</b>")
        for m in meds.values():
            taken = is_taken(chat_id, pname, m["id"])
            icon  = "✅" if taken else "🔴"
            times_str = "، ".join(m.get("times", [])) or "—"
            lines.append(f"  {icon} {m['name']} ({times_str})")

    return "\n".join(lines)


def fmt_weekly(chat_id, patients):
    lines = [f"📅 <b>ملخص آخر 7 أيام</b>\n"]
    taken_db = load_taken()

    for pname, p in patients.items():
        meds = p.get("meds", {})
        if not meds:
            continue
        lines.append(f"\n👤 <b>{pname}:</b>")
        for i in range(7):
            d    = (now_iraq() - timedelta(days=i)).strftime("%Y-%m-%d")
            dlbl = (now_iraq() - timedelta(days=i)).strftime("%a %d/%m")
            key  = f"{chat_id}:{pname}"
            t_ids    = taken_db.get(d, {}).get(key, [])
            taken_c  = len([m for m in meds.values() if m["id"] in t_ids])
            total    = len(meds)
            pct      = int(taken_c / total * 100) if total else 0
            bar      = "🟢" if pct >= 80 else ("🟡" if pct >= 50 else "🔴")
            lines.append(f"  {bar} {dlbl}: {taken_c}/{total}")

    return "\n".join(lines)

# ============================================================
# 📲 CALLBACK HANDLER
# ============================================================

def handle_callback(cb):
    chat_id  = cb["from"]["id"]
    msg_id   = cb["message"]["message_id"]
    data     = cb.get("data", "")
    cb_id    = cb["id"]
    uname    = cb["from"].get("first_name", "")

    log.info(f"👉 Received callback: {data} from {chat_id}")

    ack(cb_id)
    bot_stats["messages"] += 1
    patients = get_patients(chat_id)

    # ── Main Menu ──────────────────────────────────────────
    if data == "main_menu":
        clear_state(chat_id)
        edit(chat_id, msg_id, "⬇️ اختر من القائمة:",
             kb=kb_main_menu(bool(patients)))

    # ── Add Patient ────────────────────────────────────────
    elif data == "add_patient":
        clear_state(chat_id)
        flow_add_patient_start(chat_id)

    # ── List Patients ──────────────────────────────────────
    elif data == "list_patients":
        if not patients:
            edit(chat_id, msg_id,
                 "👥 ما عندك مرضى بعد! ابدأ بإضافة مريض:",
                 kb={"inline_keyboard": [
                     [{"text": "➕ أضف مريض", "callback_data": "add_patient"}]
                 ]})
        else:
            edit(chat_id, msg_id, "👥 <b>مرضاك:</b>\nاختر مريض:",
                 kb=kb_patients_list(patients, "patient_"))

    # ── Patient Detail ─────────────────────────────────────
    elif data.startswith("patient_"):
        pname = data[8:]
        if pname not in patients:
            edit(chat_id, msg_id, "❌ المريض مو موجود.", kb=kb_back_main())
            return
        meds_text = fmt_patient_meds(chat_id, pname, patients)
        edit(chat_id, msg_id,
             f"👤 <b>{pname}</b>\n\n{meds_text}",
             kb=kb_patient_detail(pname))

    # ── Today's meds (one patient) ─────────────────────────
    elif data.startswith("pt_today_"):
        pname = data[9:]
        p = patients.get(pname, {})
        meds = p.get("meds", {})
        if not meds:
            edit(chat_id, msg_id,
                 f"💊 {pname} ما عنده أدوية مسجلة.",
                 kb=kb_patient_detail(pname))
            return
        text = fmt_patient_meds(chat_id, pname, patients)
        edit(chat_id, msg_id, text, kb=kb_patient_detail(pname))

    # ── Today all patients ─────────────────────────────────
    elif data == "today_meds":
        edit(chat_id, msg_id, fmt_today_all(chat_id, patients),
             kb=kb_back_main())

    # ── Weekly ─────────────────────────────────────────────
    elif data == "weekly":
        edit(chat_id, msg_id, fmt_weekly(chat_id, patients),
             kb=kb_back_main())

    # ── Add med to existing patient ────────────────────────
    elif data.startswith("pt_addmed_"):
        pname = data[10:]
        flow_add_med_start(chat_id, pname)

    # ── Edit meds list for patient ─────────────────────────
    elif data.startswith("pt_editmeds_"):
        pname = data[12:]
        p     = patients.get(pname, {})
        meds  = list(p.get("meds", {}).values())
        if not meds:
            edit(chat_id, msg_id,
                 f"💊 {pname} ما عنده أدوية لتعديلها.",
                 kb=kb_patient_detail(pname))
            return
        edit(chat_id, msg_id,
             f"✏️ <b>أدوية {pname}</b>\nاختر دواء لتعديله:",
             kb=kb_meds_edit_list(meds, pname))

    # ── Select med to edit ─────────────────────────────────
    elif data.startswith("editmed_"):
        rest    = data[8:]
        pname, med_id = rest.split("|", 1)
        med = patients.get(pname, {}).get("meds", {}).get(med_id)
        if not med:
            edit(chat_id, msg_id, "❌ الدواء مو موجود.", kb=kb_back_main())
            return
        edit(chat_id, msg_id,
             f"✏️ <b>{med['name']}</b>\nشلون تريد تعدله؟",
             kb=kb_edit_field(pname, med_id))

    # ── Edit field buttons ─────────────────────────────────
    elif data.startswith("edf_"):
        parts  = data[4:].split("_", 1)  # field_pname|med_id
        field  = parts[0]
        rest   = parts[1]
        pname, med_id = rest.split("|", 1)
        flow_edit_field_start(chat_id, pname, med_id, field)

    # ── Delete med ─────────────────────────────────────────
    elif data.startswith("delmed_"):
        rest    = data[7:]
        pname, med_id = rest.split("|", 1)
        users   = load_users()
        cid     = str(chat_id)
        med     = users.get(cid, {}).get("patients", {}).get(pname, {}).get("meds", {}).pop(med_id, None)
        if med:
            save_users(users)
            edit(chat_id, msg_id,
                 f"🗑️ تم حذف <b>{med['name']}</b> من أدوية {pname}.",
                 kb=kb_patient_detail(pname))
        else:
            edit(chat_id, msg_id, "❌ الدواء مو موجود.", kb=kb_back_main())

    # ── Delete patient confirm ──────────────────────────────
    elif data.startswith("pt_del_confirm_"):
        pname = data[15:]
        edit(chat_id, msg_id,
             f"⚠️ متأكد تريد تحذف المريض <b>{pname}</b> وكل أدويته؟",
             kb={"inline_keyboard": [
                 [{"text": f"🗑️ نعم، احذف {pname}", "callback_data": f"pt_del_yes_{pname}"}],
                 [{"text": "❌ إلغاء",               "callback_data": f"patient_{pname}"}],
             ]})

    elif data.startswith("pt_del_yes_"):
        pname = data[11:]
        users = load_users()
        cid   = str(chat_id)
        users.get(cid, {}).get("patients", {}).pop(pname, None)
        save_users(users)
        patients = users.get(cid, {}).get("patients", {})
        edit(chat_id, msg_id,
             f"🗑️ تم حذف المريض <b>{pname}</b>.",
             kb=kb_main_menu(bool(patients)))

    # ── Mark taken ─────────────────────────────────────────
    elif data.startswith("mark_"):
        rest  = data[5:]
        parts = rest.split("|", 3)
        if len(parts) == 4:
            pname, med_id, time_str, med_name = parts
        else:
            pname, med_id, med_name = parts
            time_str = None
        mark_taken(chat_id, pname, med_id, time_str)
        edit(chat_id, msg_id,
             f"✅ <b>تم إعطاء {med_name} لـ{pname}!</b>\n"
             f"🕐 الوقت المسجل: {time_str or now_iraq().strftime('%H:%M')}\n\n"
             f"عاش! استمر على الانتظام 💪",
             kb=kb_back_main())

    # ── Skip ───────────────────────────────────────────────
    elif data.startswith("skip_"):
        rest  = data[5:]
        pname, med_id, time_str, med_name = rest.split("|", 3)
        mark_skipped(chat_id, pname, med_id, time_str)
        edit(chat_id, msg_id,
             f"❌ <b>تم تأكيد ترك جرعة {med_name} لـ{pname}!</b>\n"
             f"لن أقوم بتذكيرك بها مرة أخرى اليوم.",
             kb=kb_back_main())

    elif data == "already_taken":
        edit(chat_id, msg_id,
             "✅ هذا الدواء سبق وسجلته اليوم!",
             kb=kb_back_main())

    # ── Snooze ─────────────────────────────────────────────
    elif data.startswith("snooze_"):
        rest  = data[7:]
        parts = rest.split("|", 3)
        if len(parts) == 4:
            pname, med_id, time_str, med_name = parts
        else:
            pname, med_id, med_name = parts
            time_str = None
        ack(cb_id, "⏰ هذكرك بعد 10 دقائق!")

        def do_snooze(cid, pn, mid, mname, t_str):
            time.sleep(600)
            if not is_taken(cid, pn, mid, t_str) and not is_skipped(cid, pn, mid, t_str):
                send(cid,
                     f"🔔 <b>تذكير متكرر: لازم تعطي {mname} للـ{pn}!</b>",
                     kb=kb_taken(cid, pn, mid, mname, t_str))
        threading.Thread(target=do_snooze,
                          args=(chat_id, pname, med_id, med_name, time_str),
                          daemon=True).start()
        edit(chat_id, msg_id,
             f"⏰ تمام! هذكرك بـ<b>{med_name}</b> للـ{pname} بعد 10 دقائق.",
             kb=kb_back_main())

    # ── Help ───────────────────────────────────────────────
    elif data == "help":
        help_txt = (
            "ℹ️ <b>مساعدة — دكتور بوت</b>\n\n"
            "📌 <b>الأوامر:</b>\n"
            "/start — ابدأ البوت\n"
            "/menu  — القائمة الرئيسية\n"
            "/reset — مسح المحادثة والحالة\n\n"
            "📌 <b>كيف أضيف مريض؟</b>\n"
            "اضغط «➕ إضافة مريض» وأكتب الاسم، بعدين اكتب الأدوية بأي أسلوب وأنا أفهمها.\n\n"
            "📌 <b>كيف أسجل الجرعة؟</b>\n"
            "لما يجي وقت الدواء تجيك رسالة تلقائية، اضغط «✅ تم إعطاء الدواء».\n\n"
            "📌 <b>هل أقدر أضيف أكثر من مريض؟</b>\n"
            "نعم! تقدر تضيف عدد غير محدود من المرضى.\n\n"
            "📌 <b>كيف أكتب الأدوية؟</b>\n"
            "اكتب بأي شكل طبيعي:\n"
            "<code>أموكسيسيلين حبة كل 8 ساعات بعد الأكل</code>\n"
            "الذكاء الاصطناعي يفهم ويحوّله تلقائياً 🤖"
        )
        edit(chat_id, msg_id, help_txt, kb=kb_back_main())

# ============================================================
# 💬 MESSAGE HANDLER — receives text messages
# ============================================================

def handle_message(msg):
    chat_id = msg["chat"]["id"]
    text    = msg.get("text", "").strip()
    user    = msg["from"]
    name    = user.get("first_name", "صديقي")

    log.info(f"✉️ Received message: {text} from {chat_id}")

    bot_stats["messages"] += 1

    if not text:
        return

    # ── Commands ───────────────────────────────────────────
    if text.startswith("/start"):
        handle_start(chat_id, name)
        return
    if text.startswith("/reset"):
        handle_reset(chat_id)
        return
    if text.startswith("/menu"):
        handle_menu(chat_id)
        return

    # ── State Machine ──────────────────────────────────────
    st = state(chat_id)
    step = st.get("step", "idle")

    if step == "await_patient_name":
        flow_got_patient_name(chat_id, text)
        return

    if step in ("await_meds", "await_meds_for_patient"):
        # For existing patient add
        if step == "await_meds_for_patient":
            pname = st.get("pending_name", "")
            # Reuse flow_got_meds_text which saves to pending_name
        flow_got_meds_text(chat_id, text)
        return

    if step == "await_edit_value":
        flow_got_edit_value(chat_id, text)
        return

    # ── Free chat → AI ─────────────────────────────────────
    typing(chat_id)
    patients = get_patients(chat_id)
    extra_ctx = ""
    if patients:
        names = ", ".join(patients.keys())
        extra_ctx = f"المستخدم عنده المرضى التالية: {names}. تذكر هذا لو سأل عنهم."

    reply = ask_ai(chat_id, text, system_extra=extra_ctx)
    send(chat_id, reply, kb=kb_main_menu(bool(patients)))

# ============================================================
# ⏰ REMINDER SCHEDULER
# ============================================================

def minutes_since(time_str):
    """Returns whole minutes elapsed since HH:MM today. Negative = future."""
    try:
        now = now_iraq()
        h, m = map(int, time_str.split(":"))
        return now.hour * 60 + now.minute - (h * 60 + m)
    except:
        return -1


def reminder_loop():
    """Check every 60 seconds. Fire at dose time, repeat every 10 min until taken/skipped."""
    log.info("⏰ Reminder scheduler started")
    sent_today     = set()   # (cid, pname, med_id, time_str, attempt)
    last_reset_day = today()

    while True:
        try:
            now          = now_iraq()
            current_time = now.strftime("%H:%M")

            # Reset tracking set at midnight
            if today() != last_reset_day:
                sent_today.clear()
                last_reset_day = today()
                log.info("🔄 Reminder tracker reset for new day.")

            users = load_users()

            for cid, user in users.items():
                chat_id  = user.get("chat_id") or int(cid)
                patients = user.get("patients", {})

                for pname, p in patients.items():
                    for med in p.get("meds", {}).values():
                        for t in med.get("times", []):
                            mins = minutes_since(t)
                            if mins < 0:
                                continue  # dose time not reached yet
                            if mins % 10 != 0:
                                continue  # only fire at 0, 10, 20... minutes after dose

                            attempt  = mins // 10
                            sent_key = (cid, pname, med["id"], t, attempt)

                            if sent_key in sent_today:
                                continue  # already sent this attempt

                            # Mark it regardless so we don't double-send
                            sent_today.add(sent_key)

                            if is_taken(chat_id, pname, med["id"], t):
                                continue  # already confirmed
                            if is_skipped(chat_id, pname, med["id"], t):
                                continue  # user said skip

                            send_reminder(chat_id, pname, med, t)
                            bot_stats["reminders_sent"] += 1
                            log.info(f"🔔 Reminder: {pname} / {med['name']} @ {t} (attempt {attempt})")

            # Daily expiry warnings at 08:00
            if current_time == "08:00":
                for cid, user in users.items():
                    chat_id = user.get("chat_id") or int(cid)
                    key = ("expiry", cid, today())
                    if key not in sent_today:
                        sent_today.add(key)
                        send_expiry_warnings(chat_id, user.get("patients", {}))

            # Missed dose report at 22:00
            if current_time == "22:00":
                for cid, user in users.items():
                    chat_id = user.get("chat_id") or int(cid)
                    key = ("missed", cid, today())
                    if key not in sent_today:
                        sent_today.add(key)
                        send_missed_check(chat_id, user.get("patients", {}))

            # Weekly summary every Sunday 09:00
            if now.weekday() == 6 and current_time == "09:00":
                for cid, user in users.items():
                    chat_id = user.get("chat_id") or int(cid)
                    key = ("weekly", cid, today())
                    if key not in sent_today:
                        sent_today.add(key)
                        msg = fmt_weekly(chat_id, user.get("patients", {}))
                        send(chat_id, msg, kb=kb_main_menu(True))

            time.sleep(60)  # one check per minute

        except Exception as e:
            log.error(f"[reminder_loop] {e}")
            time.sleep(60)



def send_reminder(chat_id, pname, med, time_str):
    """Send a single medication reminder with confirm button."""
    status, days = expiry_info(med.get("expiry", ""))
    exp_note = ""
    if status == "warning":
        exp_note = f"\n⚠️ <b>الدواء ينتهي بعد {days} يوم!</b>"
    elif status == "expired":
        exp_note = f"\n❌ <b>الدواء منتهي الصلاحية! راجع الطبيب!</b>"

    text = (
        f"🔔 <b>وقت الدواء! ({time_str})</b>\n\n"
        f"👤 المريض: <b>{pname}</b>\n"
        f"💊 الدواء: <b>{med['name']}</b>"
        + (f"\n📋 الجرعة: {med['dosage']}" if med.get("dosage") else "")
        + f"\n🕐 {now_iraq().strftime('%H:%M')}"
        + exp_note
        + "\n\nهل تم إعطاء الدواء؟ 👇"
    )
    send(chat_id, text,
         kb=kb_taken(chat_id, pname, med["id"], med["name"], time_str))


def send_expiry_warnings(chat_id, patients):
    """Daily 08:00 expiry check."""
    warns = []
    for pname, p in patients.items():
        for med in p.get("meds", {}).values():
            status, days = expiry_info(med.get("expiry", ""))
            if status == "warning":
                warns.append(f"⚠️ <b>{med['name']}</b> ({pname}) — باقي {days} يوم")
            elif status == "expired":
                warns.append(f"❌ <b>{med['name']}</b> ({pname}) — منتهي الصلاحية!")
    if warns:
        txt = "🔔 <b>تنبيه يومي — صلاحية الأدوية</b>\n\n" + "\n".join(warns)
        txt += "\n\n⚕️ راجع طبيبك لتجديد الوصفة!"
        send(chat_id, txt, kb=kb_main_menu(True))


def send_missed_check(chat_id, patients):
    """22:00 check for missed doses."""
    missed = []
    for pname, p in patients.items():
        for med in p.get("meds", {}).values():
            if med.get("times") and not is_taken(chat_id, pname, med["id"]):
                missed.append(f"❌ <b>{med['name']}</b> — {pname}")
    if missed:
        txt = (
            "😟 <b>تذكير مسائي — جرعات فايتة</b>\n\n"
            + "\n".join(missed)
            + "\n\n⚕️ استشر طبيبك إذا فاتتك جرعة مهمة."
        )
        send(chat_id, txt, kb=kb_main_menu(True))

# ============================================================
# 🤖 MAIN BOT LOOP
# ============================================================

def run_bot():
    log.info("🤖 Bot polling started")
    offset = None

    while True:
        try:
            updates = get_updates(offset)
            for update in updates:
                offset = update["update_id"] + 1

                if "callback_query" in update:
                    cb = update["callback_query"]
                    try:
                        handle_callback(cb)
                    except Exception as e:
                        log.error(f"[callback] {e}")
                    continue

                if "message" in update:
                    try:
                        handle_message(update["message"])
                    except Exception as e:
                        log.error(f"[message] {e}")

        except Exception as e:
            log.error(f"[run_bot] {e}")
            time.sleep(5)

# ============================================================
# 🏁 ENTRY POINT
# ============================================================

if __name__ == "__main__":
    log.info("=" * 55)
    log.info("💊 دكتور بوت v3 — AI Multi-Patient Medication Bot")
    log.info("=" * 55)
    log.info(f"BOT_TOKEN:    {'✅' if BOT_TOKEN    else '❌ MISSING'}")
    log.info(f"GROQ_API_KEY: {'✅' if GROQ_API_KEY else '❌ MISSING (AI disabled)'}")

    if not BOT_TOKEN:
        log.error("❌ BOT_TOKEN is missing! Set it as an environment variable.")
        exit(1)

    # Clear any active webhook so polling works cleanly
    try:
        r = requests.post(f"{BASE_URL}/deleteWebhook", json={"drop_pending_updates": False}, timeout=10)
        log.info(f"📡 deleteWebhook: {r.json().get('description', 'ok')}")
    except Exception as e:
        log.warning(f"deleteWebhook failed: {e}")

    # Bot polling thread
    threading.Thread(target=run_bot,       daemon=True, name="BotLoop").start()
    # Reminder scheduler thread
    threading.Thread(target=reminder_loop, daemon=True, name="Reminders").start()

    log.info("🚀 Bot is running! Press Ctrl+C to stop.")

    # Keep main thread alive
    try:
        while True:
            time.sleep(60)
            log.info(f"📊 Stats — Messages: {bot_stats['messages']}, Reminders: {bot_stats['reminders_sent']}")
    except KeyboardInterrupt:
        log.info("🛑 Bot stopped by user.")
