# Apex Arena Mobile (Godot 4.x, GDScript, بدون صدا)

## ساختار فایل‌ها
- `project.godot`, `export_presets.cfg`
- `Scenes/Main.tscn`  (فقط ریشه؛ همه چیز با کد ساخته می‌شود)
- `Systems/game.gd`   منو، لابی آنلاین، تایمر ۴ دقیقه، امتیاز، respawn، تنظیمات
- `Systems/net.gd`    شبکه: هاست/جوین با هات‌اسپات (ENet) + پیدا کردن خودکار هاست
- `Player/player.gd`  حرکت: sprint, slide, slide-jump, bunny hop, strafe، تیلت اسلحه، ژیرسکوب
- `Player/remote_player.gd`  بازیکن دوست (روی گوشی دوم) در بازی آنلاین
- `Weapons/weapon.gd`, `Weapons/weapon_data.gd`  تفنگ ریفل + تپانچه
- `Enemies/enemy.gd`  هوش مصنوعی دشمن (بات)
- `Arena/arena.gd`    زمین، دیوار، سنگر
- `Input/touch_controls.gd`  جوی‌استیک، دکمه‌ها، multi-touch، چرخش دوربین، ژیرسکوب
- `UI/hud.gd`  HUD   |  `Effects/effects.gd`  جرقه و ردگلوله

## ساخت APK
1. Godot 4.x + Export Templates را نصب کنید.
2. JDK 17 و Android SDK نصب کنید و در Editor Settings > Export > Android مسیرها را بدهید.
3. Project > Export > Android > Export Project (Debug) > `ApexArena.apk`.
(دسترسی‌های اینترنت/وای‌فای برای بازی آنلاین در export_presets.cfg فعال شده‌اند.)

## بازی با دوست (هات‌اسپات)
1. گوشی A: هات‌اسپات را روشن کن > بازی > PLAY WITH FRIEND > HOST GAME
2. گوشی B: به وای‌فای هات‌اسپات A وصل شو > PLAY WITH FRIEND > JOIN GAME (خودکار)
3. اگر خودکار وصل نشد: IP نمایش‌داده‌شده روی گوشی A (معمولاً 192.168.43.1) را در کادر IP بنویس و CONNECT.
با وای‌فای مشترک خانه هم کار می‌کند. هاست زمان ۴ دقیقه را کنترل می‌کند و فقط هاست می‌تواند PLAY AGAIN بزند.

## ژیرسکوب
- دکمه II > تنظیمات: GYRO ON/OFF، GYRO SENSITIVITY (کم/زیاد کردن سرعت)، کالیبراسیون.
- CALIBRATE GYRO: گوشی را روی میز بگذار و بزن؛ انحراف (drift) سنسور حذف می‌شود.
- اگر جهت‌ها برعکس یا جابه‌جا بود: FLIP H (چپ/راست)، FLIP V (بالا/پایین)، AXES SWAP.
- خط آبی "GYRO x y z" در منوی توقف مقادیر زنده سنسور را نشان می‌دهد (اگر همیشه صفر بود یعنی سنسور فعال نیست).

## کنترل‌ها
استیک چپ = حرکت (تا لبه = sprint) | کشیدن روی صفحه راست یا روی FIRE/AIM = چرخش
SLIDE نگه‌دارید در حین دویدن = slide | JUMP حین slide = slide-jump | JUMP درست قبل/بعد از فرود = bunny hop
در slide چپ/راست = strafe و تیلت اسلحه | دکمه II = تنظیمات
