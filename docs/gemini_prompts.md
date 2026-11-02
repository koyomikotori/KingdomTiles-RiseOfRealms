# Prompt Gemini cho chân dung (cùng một phong cách)

Mục tiêu: mọi chân dung trong game (tướng, mưu sĩ, NPC, chúa công) cùng một nét vẽ của Gemini.
Cách làm: vẽ **1 mẫu chung** trước, rồi gửi kèm mẫu đó (ảnh tham chiếu) mỗi khi vẽ nhân vật mới.

Prompt viết bằng tiếng Anh (Gemini hiểu chính xác hơn). Kích thước, nền và cách đưa vào game xem
`docs/portrait_ai_guide.md`; ảnh gốc giữ trong `initial/ai_sources/`, rồi chạy:

```
python tools/art/fix_portraits.py <ảnh gốc> assets/portraits/pool/<tên>.png
```

## 1. Khối phong cách (dán vào cuối MỌI prompt)

```
Style: chunky pixel art portrait, the whole image is a 96x96 pixel grid scaled up evenly (every
pixel is a clean square block), anime face with large expressive eyes, 1-pixel dark brown
outline, flat cel shading with 2-3 tones per color, bright saturated Kairosoft-like palette,
no gradients, no anti-aliasing, no blur. Bust shot from the chest up, facing the viewer or a
slight 3/4 turn, head about half of the image height, about 5% empty space above the head.
Ancient East Asian fantasy setting. Background: one flat solid pure green color #00FF00, no
scenery, no shadow on the background, no frame, no border, no text, no signature. Square image.
```

## 2. Mẫu chung (vẽ một lần, dùng làm ảnh tham chiếu)

Gửi kèm 2–3 chân dung cũ của Gemini mà bạn thích nhất (ví dụ `advisor_f_11`, `general_m_11`,
`advisor_m_05` trong `initial/ai_sources/`), rồi dùng prompt:

```
Using the attached images as the style reference, draw a style sheet: 4 pixel art bust
portraits side by side in one row, evenly spaced, same size and same art style: a young male
general in gold lamellar armor with a pheasant-feather helmet, a female general in light armor
with a high ponytail, an old male strategist in a blue scholar robe holding a white feather
fan, a female strategist with a jade hairpin and a blue robe. They must look like they were
drawn by the same artist for the same game: same pixel size, same outline, same shading, same
eye style, same color saturation.
```

Ưng ý thì lưu ảnh này thành `initial/ai_sources/style_sheet.png`. Từ đây, **mỗi prompt bên
dưới đều gửi kèm ảnh mẫu chung** và mở đầu bằng:

```
Match the art style of the attached reference sheet exactly (pixel size, outline, shading, eyes,
colors). Draw ONE character only.
```

## 3. Vẽ lại hai nhân vật của Grok

Hai ảnh này lệch phong cách so với phần còn lại. Vẽ xong thì **ghi đè đúng tên file cũ** để
những tướng đang dùng ảnh đó trong bản lưu vẫn giữ người của mình.

**`advisor_f_05`** — nữ mưu sĩ tóc bạc tết bím, cầm chén trà:

```
A calm young woman strategist with long silver-gray hair in one thick braid over her right
shoulder, a dark knotted hair ornament with a jade-green tassel, gentle half-closed red eyes,
a faint smile. She wears a layered charcoal-gray scholar robe with a subtle wave pattern and a
dark sash with a gold cord, and holds a small celadon tea cup with both hands in front of her
chest.
```

**`advisor_m_18`** — mưu sĩ tóc đỏ đeo đàn tỳ bà:

```
A young male strategist and musician with messy crimson-red hair covering one eye, a cool
calm expression, red eyes. He wears a long white coat with a high collar, red and gold trim and
gold patterns, over a black inner robe, with a dark leather strap across his chest. A wooden
pipa lute with a red tassel hangs on his back, its neck showing over his left shoulder.
```

**`advisor_m_04`** — mưu sĩ trẻ áo xanh lục, ôm cuộn trúc giản:

```
A young male strategist with shoulder-length messy black hair under a black scholar's cap with
a gold ornament at the front, sharp thoughtful dark eyes, a slight confident smile. He wears a
jade-green scholar robe with a white crossed collar and darker green trim, and holds a rolled
bamboo scroll tied with a brown cord against his chest.
```

## 4. NPC lái buôn chợ đen (tùy chọn)

Hiện là hình ghép bằng script nên chưa cùng nét với tướng. Vẽ xong, xử lý bằng
`fix_portraits.py` và lưu thành `assets/portraits/custom/black_market.png`: game ưu tiên ảnh
này thay cho hình ghép (file trong `npc/` bị script vẽ lại mỗi lần chạy `generate.py`).

```
A mysterious black market merchant: a wide conical straw hat pulled low so only a sly grin
and glinting eyes show in the shadow, a dark hooded cloak over a deep purple robe, a small gold
coin pouch and a jade token hanging at the chest, one gloved hand raised showing a gold coin
between two fingers. A small paper lantern glows warm orange behind his shoulder.
```

## 5. Chúa công (6 mẫu)

Ảnh tham khảo là nhân vật có bản quyền, mà game sẽ phát hành, nên prompt **không ghi tên nhân
vật / tác phẩm**, **không gửi kèm ảnh tham khảo đó cho Gemini**, và mỗi người được đổi kiểu
tóc, màu mắt, tư thế, vũ khí và trang phục (cổ phong Á Đông). Chỉ giữ ý chung: chiến binh tóc
vàng, thiên tử tóc đen, mưu sĩ tóc bạc, tông trắng – xanh lam – vàng.
Gửi kèm **ảnh mẫu chung** và mở đầu bằng:

```
Match the art style of the attached reference sheet exactly (pixel size, outline, shading,
eyes, colors). Design an original character. Draw ONE character only.
```

Màu "phe" là **xanh lam** (áo choàng, dải lụa…) để sau này đổi theo màu vương quốc được.
Lưu ảnh gốc vào `initial/ai_sources/ruler_<số>_gemini.png` rồi gửi mình.

### Chúa công chiến binh (tóc vàng)

**`ruler_3` — Nữ tướng quân:**

```
A bold young warrior queen with long golden blonde hair in a high ponytail held by a gold hair
ring, warm amber eyes, a fearless grin. She wears East Asian lamellar armor of small gold-edged
steel scales with rounded shoulder guards shaped like cloud scrolls, a royal-blue silk war
mantle draped over one shoulder, and holds an upright ji halberd with a red tassel beside her.
```

**`ruler_2` — Bá vương:**

```
A young warlord king with shoulder-length golden blonde hair swept back and tied low at the
nape, light stubble, steady brown eyes, a proud half smile. He wears heavy dark-steel lamellar
armor with gold lion-head shoulder guards and a gold belt buckle, a royal-blue war cloak, and
rests a broad heavy dao saber on his shoulder.
```

### Chúa công thiên tử (tóc đen)

**`ruler_1` — Nữ hoàng:**

```
A graceful young empress with black hair in an elaborate high updo, a gold phoenix crown with
dangling pearl strings, deep amber eyes, a serene composed smile. She wears a white imperial
robe embroidered with gold phoenixes and clouds, a royal-blue silk shawl over her arms, and
holds a jade ruyi scepter in both hands.
```

**`ruler_0` — Thiên tử:**

```
A young emperor with black hair in a neat topknot under a small gold crown cap with a jade
pin, dark brown eyes, a calm dignified expression. He wears a black dragon robe with red and
gold trim and a gold coiled dragon on the chest, a royal-blue sash at the waist, and rests one
hand on the hilt of a straight jian sword at his side.
```

### Chúa công mưu sĩ (tóc bạc / bạch kim)

**`ruler_5` — Nữ mưu sĩ:**

```
A kind young woman sage-ruler with shoulder-length platinum silver hair and one thin side
braid fastened with a jade hairpin, pale blue eyes, a soft knowing smile. She wears a white
scholar robe with silver cloud embroidery, a small navy gauze scholar's cap, a royal-blue
sleeveless over-robe with silver trim, and holds an open bamboo-slip book.
```

**`ruler_4` — Nam mưu sĩ:**

```
A young cunning strategist lord with silver hair in a half-up topknot and loose strands at the
temples, cool gray eyes, a thin scheming smile. He wears a deep royal-blue official's robe with
silver crane embroidery over a white inner robe, a black lacquered hair crown, and holds a
single white go stone between two raised fingers.
```

Số `ruler_<số>` theo thứ tự mẫu trong game: 0 Thiên tử, 1 Nữ hoàng, 2 Bá vương, 3 Nữ tướng
quân, 4 Mưu chủ, 5 Nữ mưu chủ. **Đã có đủ 6 ảnh** trong `assets/portraits/ruler/`; vẽ lại thì
chạy `fix_portraits.py` và ghi đè đúng tên file.
