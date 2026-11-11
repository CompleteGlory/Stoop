"""Writes the app's String Catalogs (English source, Arabic translations).

Run from the repo root:  python3 tools/strings/make_strings.py PlaceRating/Resources
Add a new user-facing string here with its Arabic translation, then run it again.
"""
import json, sys, os
root = sys.argv[1]
strings = {
    "Your friends, your places, one map": "أصدقاؤك وأماكنك على خريطة واحدة",
    "By continuing you accept the Terms and Privacy Policy.": "بالمتابعة فإنك توافق على الشروط وسياسة الخصوصية.",
    "Pick your name": "اختر اسمك",
    "This is how friends see you on the map.": "هكذا يراك أصدقاؤك على الخريطة.",
    "Use a different Apple ID": "استخدم حساب Apple آخر",
    "Checking…": "جارٍ التحقق…",
    "Available": "متاح",
    "Continue": "متابعة",
    "Sign out": "تسجيل الخروج",
    "Try again": "حاول مرة أخرى",
    "We couldn't reach the server.": "تعذّر الوصول إلى الخادم.",
    "Your session has expired. Sign in again.": "انتهت جلستك. سجّل الدخول مرة أخرى.",
    "Something went wrong. Try again.": "حدث خطأ ما. حاول مرة أخرى.",
    "That username is taken.": "اسم المستخدم هذا مأخوذ.",
    "That username isn't available.": "اسم المستخدم هذا غير متاح.",
    "Use 3 to 20 letters, digits, _ or .": "استخدم من 3 إلى 20 حرفًا إنجليزيًا أو رقمًا أو _ أو .",
    "Too many attempts. Try again later.": "محاولات كثيرة جدًا. حاول لاحقًا.",
    "Sign in failed. Try again.": "فشل تسجيل الدخول. حاول مرة أخرى.",
    "That character couldn't be saved. Try another look.": "تعذّر حفظ الشخصية. جرّب مظهرًا آخر.",
    "Make your character": "اصنع شخصيتك",
    "Friends see it on the map.": "يراها أصدقاؤك على الخريطة.",
    "Style": "النمط",
    "Hairstyles": "تسريحات الشعر",
    "Male": "ذكر",
    "Female": "أنثى",
    "Surprise me": "فاجئني",
    "Hair": "الشعر",
    "Hair color": "لون الشعر",
    "Skin": "البشرة",
    "Eyes": "العينان",
    "Eye color": "لون العينين",
    "Eyebrows": "الحاجبان",
    "Eyebrow color": "لون الحاجبين",
    "Mouth": "الفم",
    "Nose": "الأنف",
    "Facial hair": "شعر الوجه",
    "Facial hair color": "لون شعر الوجه",
    "Outfit": "الملابس",
    "Outfit color": "لون الملابس",
    "Accessories": "الإكسسوارات",
    "Accessory color": "لون الإكسسوارات",
    "Glasses": "النظارات",
    "Glasses color": "لون النظارات",
    "Earrings": "الأقراط",
    "Earring color": "لون الأقراط",
    "Details": "تفاصيل",
    "Hat color": "لون القبعة",
    "Face": "الوجه",
    "Next": "التالي",
    "Back": "رجوع",
}
plist = {
    "NSLocationWhenInUseUsageDescription": (
        "Your location is shown to friends you accept, while the app is open.",
        "يظهر موقعك للأصدقاء الذين تقبلهم أثناء فتح التطبيق.",
    ),
}
def unit(v): return {"stringUnit": {"state": "translated", "value": v}}
def write(name, body):
    with open(os.path.join(root, name), "w", encoding="utf-8") as f:
        json.dump({"sourceLanguage": "en", "strings": body, "version": "1.0"}, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
write("Localizable.xcstrings", {k: {"localizations": {"ar": unit(v)}} for k, v in strings.items()})
write("InfoPlist.xcstrings", {k: {"localizations": {"en": unit(e), "ar": unit(a)}} for k, (e, a) in plist.items()})
