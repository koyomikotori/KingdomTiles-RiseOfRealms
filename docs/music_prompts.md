# Prompt làm nhạc nền (cho AI làm nhạc)

Dùng cho Suno, Udio hoặc plugin làm nhạc (Abracadabrax, CellCog…). Prompt viết bằng tiếng Anh vì các AI nhạc hiểu tiếng Anh tốt nhất. Mỗi bài chọn chế độ **Instrumental** (không lời).

## Cách đưa vào game

- Xuất file **.ogg** (hoặc .wav / .mp3), đặt **đúng tên** dưới đây.
- Thử ngay: thả vào `assets/audio/custom/`, game sẽ dùng file đó thay cho bản cũ.
- Khi chốt bài: đưa mình file, mình thay hẳn trong `assets/audio/music/` trước khi build.
- Nhạc nền phát **lặp lại**: nên cắt bỏ đoạn mở đầu dài và đoạn kết fade-out, để hết bài nối lại đầu bài không bị hụt. Bài ngắn (victory, defeat) chỉ phát một lần.

## Phong cách chung (dán vào mọi bài)

> Retro 16-bit / chiptune-inspired game soundtrack, East Asian pentatonic melody, small kingdom management sim, warm and charming, cozy pixel-art game, light percussion, instrumental, no vocals, seamless loop

## Từng bài

| Tên file | Lúc phát | Độ dài |
|---|---|---|
| `menu` | Menu chính (sau có cảnh trận đánh mờ) | 1:30–2:00 |
| `kingdom` | Bản đồ vương quốc, chơi lâu nhất | 2:30–3:30 |
| `battle` | Màn hình trận đánh | 1:30–2:00 |
| `expedition` | Màn phát lại thảo phạt (đội hành quân, phục kích) | 1:00–1:30 |
| `victory` | Thắng trận / thắng ván, phát 1 lần | 4–8 giây |
| `defeat` | Thua trận / thất bại, phát 1 lần | 4–8 giây |

**menu**
> Main menu theme for a pixel-art kingdom-building strategy game. Majestic but gentle opening feel, East Asian pentatonic melody on koto-like plucked lead and bamboo flute, soft taiko and hand drums, warm retro 16-bit synth pads, mid tempo around 90 BPM, hopeful and inviting, instrumental, seamless loop, no long intro, no fade-out.

**kingdom**
> Peaceful kingdom-building background music for a cozy pixel-art strategy game played for hours. Calm and pleasant, never tiring, East Asian pentatonic melody on plucked strings (koto / guzheng style) and soft flute, light marimba and gentle hand percussion, retro 16-bit chiptune warmth, relaxed tempo around 80–90 BPM, village life, farming and building, bright daytime mood, low intensity, instrumental, seamless loop, no fade-out.

**battle**
> Energetic battle theme for a pixel-art strategy game with armies clashing on a field. Driving taiko war drums, fast East Asian pentatonic melody on erhu-like lead and bright retro 16-bit square-wave synths, brass-like stabs, tense and heroic, tempo around 140 BPM, exciting but not chaotic, instrumental, seamless loop, no fade-out.

**expedition**
> Adventurous marching theme for a side-scrolling expedition: a small army marches through hills and gets ambushed by bandits. Upbeat and bold, steady marching snare and taiko, East Asian pentatonic melody on bamboo flute and plucked strings, retro 16-bit chiptune flavor, tempo around 125 BPM, playful heroism, instrumental, seamless loop, no fade-out.

**victory**
> Short victory jingle for a pixel-art strategy game, 6 seconds, triumphant fanfare, East Asian pentatonic melody, gong hit and taiko roll, retro 16-bit synth brass, ends on a bright resolved chord, instrumental.

**defeat**
> Short defeat jingle for a pixel-art strategy game, 6 seconds, sad descending East Asian pentatonic melody on a lone flute over a soft low drum, retro 16-bit tone, ends quietly on an unresolved minor note, instrumental.

## Lưu ý

- Đọc điều khoản của dịch vụ: nhiều nơi chỉ cho dùng nhạc trong game (kể cả bán) khi bạn dùng **gói trả phí**. Bản cho bạn bè chơi thì thường không sao, nhưng nếu sau này bán game thì cần gói có quyền thương mại.
- Mỗi prompt nên tạo vài bản rồi chọn bản nghe hợp nhất. Giữ cùng "phong cách chung" để cả bộ nhạc nghe đồng bộ.
- Ghi lại tên dịch vụ đã dùng: mình sẽ đưa vào bảng "Giới thiệu / Bản quyền" của game.
