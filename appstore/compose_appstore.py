# App Store screenshots: brand arc + soft color blobs behind the device,
# two-tone Cormorant headline, Helvetica Neue subline. 1284x2778 (the size
# App Store Connect accepts for the 6.5"/6.9" slot).
# Raw device shots live in raw/, output lands next to this script.
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

BASE = os.path.dirname(os.path.abspath(__file__))
CORMORANT = os.path.join(BASE, '..', 'ios', 'MamaYaRyadom', 'Resources', 'Fonts',
                         'CormorantGaramond-SemiBold.ttf')
NEUE = '/System/Library/Fonts/HelveticaNeue.ttc'

W, H = 1284, 2778
BG = (245, 240, 231)
INK = (51, 41, 31)
SUB = (122, 111, 98)
HONEY = (184, 121, 26)
CHERRY = (142, 58, 76)

f_head = ImageFont.truetype(CORMORANT, 105)
f_sub = ImageFont.truetype(NEUE, 45, index=0)

def bez(t, p0, p1, p2):
    return ((1-t)**2*p0[0] + 2*(1-t)*t*p1[0] + t**2*p2[0],
            (1-t)**2*p0[1] + 2*(1-t)*t*p1[1] + t**2*p2[1])

def rounded_mask(size, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0]-1, size[1]-1], radius=radius, fill=255)
    return m

def compose(src, dst, head_lines, subline, shot_top=545, shot_w=1148):
    canvas = Image.new('RGB', (W, H), BG)

    blobs = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(blobs)
    bd.ellipse([W-620, 240, W+240, 1100], fill=(184, 121, 26, 56))
    bd.ellipse([-300, 1900, 460, 2660], fill=(142, 58, 76, 40))
    bd.ellipse([-260, 120, 360, 740], fill=(63, 122, 78, 30))
    blobs = blobs.filter(ImageFilter.GaussianBlur(160))
    canvas = Image.alpha_composite(canvas.convert('RGBA'), blobs)

    arc = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arc)
    p0, p1, p2 = (40, 1500), (W//2, 300), (W-40, 1500)
    for i in range(1, 30):
        t = i / 30
        x, y = bez(t, p0, p1, p2)
        ad.ellipse([x-11, y-11, x+11, y+11], fill=(184, 121, 26, 96))
    canvas = Image.alpha_composite(canvas, arc)
    draw = ImageDraw.Draw(canvas)

    y = 150
    for segments in head_lines:
        total = sum(draw.textlength(t, font=f_head) for t, _ in segments)
        x = (W - total) / 2
        for t, color in segments:
            draw.text((x, y), t, font=f_head, fill=color)
            x += draw.textlength(t, font=f_head)
        y += 120

    sw = draw.textlength(subline, font=f_sub)
    draw.text(((W - sw) / 2, y + 26), subline, font=f_sub, fill=SUB)

    shot = Image.open(os.path.join(BASE, 'raw', src)).convert('RGB')
    th = round(shot.height * shot_w / shot.width)
    shot = shot.resize((shot_w, th), Image.LANCZOS)
    radius = 78
    sx = (W - shot_w) // 2
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [sx - 6, shot_top + 20, sx + shot_w + 6, shot_top + th],
        radius=radius, fill=(51, 41, 31, 74))
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.paste(shot, (sx, shot_top), rounded_mask((shot_w, th), radius))

    canvas.convert('RGB').save(os.path.join(BASE, dst), optimize=True)
    print(dst)

compose('shot-today.png', 'appstore-1.png',
        [[('Она нажала кнопку.', INK)], [('Ты ', INK), ('выдыхаешь', HONEY), ('.', INK)]],
        'Каждое утро мама отвечает одной кнопкой в Telegram')

compose('shot-history.png', 'appstore-2.png',
        [[('Спокойные дни', INK)], [('складываются в ', INK), ('месяцы', HONEY)]],
        'Весь месяц заботы — на одном экране')

compose('shot-day.png', 'appstore-3.png',
        [[('Не догадки —', INK)], [('её слова', CHERRY)]],
        'Ты видишь её сообщение — а не тишину')

compose('shot-postcard.png', 'appstore-4.png',
        [[('Пара ', INK), ('тёплых слов', HONEY), (' —', INK)], [('прямо ей в Telegram', INK)]],
        'Ты пишешь в приложении — мама получает открытку от бота')

compose('shot-two.png', 'appstore-5.png',
        [[('Мама и папа —', INK)], [('на ', INK), ('одном', HONEY), (' экране', INK)]],
        'У каждого — своё утро и свой часовой пояс')

# ── English series ───────────────────────────────────────────────────────────

compose('shot-today-en.png', 'appstore-en-1.png',
        [[('She taps a button.', INK)], [('You ', INK), ('breathe out', HONEY), ('.', INK)]],
        'Every morning mom answers with one button in Telegram')

compose('shot-history-en.png', 'appstore-en-2.png',
        [[('Calm days', INK)], [('add up to ', INK), ('months', HONEY)]],
        'A whole month of care on one screen')

compose('shot-day-en.png', 'appstore-en-3.png',
        [[('Not guesses —', INK)], [('her own words', CHERRY)]],
        'You see her message — not silence')

compose('shot-postcard-en.png', 'appstore-en-4.png',
        [[('A few ', INK), ('warm words', HONEY), (' —', INK)], [('straight to her Telegram', INK)]],
        'You write in the app — mom gets a postcard from the bot')

compose('shot-two-en.png', 'appstore-en-5.png',
        [[('Mom and dad —', INK)], [('on ', INK), ('one', HONEY), (' screen', INK)]],
        'Each with their own morning and their own time zone')
