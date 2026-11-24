extends RefCounted

## Lớp học THPT Bình Kê (GDD 6: T2–T6 học 2 tiết sáng, +5 Technology/tiết; quiz đúng +2 Technology – GDD 7.1).
## Hai tiết, mỗi tiết một môn (Công nghệ / Sinh học luôn có một tiết), mỗi tiết PER_PERIOD câu hỏi bằng
## DialogBox.choose. Nhiều câu kiêm luôn mẹo chơi (Technology → Biotech, ấp trứng, đột biến, Thể trạng…).
## Đáp án đúng luôn là phương án đầu trong QUESTIONS; thứ tự hiển thị được xáo.
## current_answer: chỉ số đáp án đúng của câu đang hỏi (test đọc để trả lời).

const TEACHER: String = "Thầy Khoa"
const PER_PERIOD: int = 2
const TECH_PER_RIGHT: int = 2
const SUBJECTS: Dictionary = {
	"Công nghệ": [
		{"q": "Mười điểm Technology đổi được mấy Biotech ở bàn học?", "a": ["1 Biotech", "10 Biotech", "5 Biotech", "Hổng đổi được"],
			"why": "10 Technology → 1 Biotech. Đi học đều là có Biotech để đột biến gà."},
		{"q": "Lò ấp trứng cần gì ngoài quả trứng?", "a": ["Biotech", "Nước đá", "Muối hột", "Tiền lẻ"],
			"why": "Bỏ trứng vô lò kèm Biotech; bỏ dư Biotech thì gà con dễ có đột biến."},
		{"q": "Muốn gắn cựa, mào cho gà thì làm ở đâu?", "a": ["Chuồng gà ở nhà (hoặc màn chuẩn bị trước trận)", "Ngoài chợ", "Ở trường", "Xe khô gà Lão Gà Khô"],
			"why": "Mua đồ xong về chuồng gà gắn, hoặc thay ở màn chuẩn bị trước trận."},
		{"q": "Một cái máy bơm nước dùng điện 220V. Vậy 220 là gì?", "a": ["Hiệu điện thế", "Cân nặng", "Nhiệt độ", "Tốc độ"],
			"why": "220V là hiệu điện thế lưới điện nhà mình."},
	],
	"Sinh học": [
		{"q": "Đột biến «Cơ Nhanh» làm gà lẹ hơn, mà đánh đổi cái gì?", "a": ["Bớt máu (HP)", "Hổng mất gì", "Bớt cựa", "Rụng lông"],
			"why": "Đột biến nào cũng có đánh đổi: Cơ Nhanh +SPD nhưng −HP."},
		{"q": "Gà bị bỏ đói một ngày thì sao?", "a": ["Thể trạng giảm", "Mạnh lên", "Đẻ trứng", "Hổng sao hết"],
			"why": "Bỏ đói −20% Thể trạng. Thể trạng dưới 50% là ATK giảm 10%."},
		{"q": "Giải Olympic Đá Gà chỉ nhận gà có ít nhất mấy đột biến?", "a": ["Ba đột biến", "Một đột biến", "Mười đột biến", "Hổng cần"],
			"why": "Luật Hell Mode: gà phải qua ít nhất 3 đột biến mới được đăng ký."},
		{"q": "Gà Đông Tảo nổi tiếng nhờ đặc điểm gì?", "a": ["Chân to, nặng ký", "Biết bay xa", "Lông màu xanh", "Gáy ban đêm"],
			"why": "Đông Tảo chân to, lì đòn, khó bị đẩy lùi."},
	],
	"Toán": [
		{"q": "Một bao lúa 15.000đ, gà ăn mỗi ngày một bao. Một tuần tốn bao nhiêu?", "a": ["105.000đ", "75.000đ", "150.000đ", "15.000đ"],
			"why": "15.000 × 7 = 105.000đ. Nuôi gà là phải tính!"},
		{"q": "Chở ghe một ca được 100.000đ. Muốn mua Mũ đồng 650.000đ cần ít nhất mấy ca?", "a": ["7 ca", "5 ca", "6 ca", "65 ca"],
			"why": "6 ca mới có 600.000đ, phải 7 ca mới đủ."},
	],
	"Ngữ văn": [
		{"q": "Câu «Gà nhà bôi mặt đá nhau» khuyên điều gì?", "a": ["Người một nhà đừng hại nhau", "Gà phải bôi mặt", "Nên nuôi nhiều gà", "Đá gà ban đêm"],
			"why": "Người trong nhà phải thương nhau, đừng như gà nhà bôi mặt đá nhau."},
		{"q": "Truyện Sơn Tinh – Thủy Tinh có sính lễ gà mấy cựa?", "a": ["Chín cựa", "Hai cựa", "Một cựa", "Mười cựa"],
			"why": "Voi chín ngà, gà chín cựa, ngựa chín hồng mao."},
	],
}
const PRAISE: Array[String] = ["Giỏi! Cộng điểm miệng.", "Đúng rồi, ngồi xuống em.", "Chính xác. Cả lớp vỗ tay cho bạn!"]

var current_answer: int = -1


## Kế hoạch hai tiết cho trang lớp học (quiz_page.gd): {subjects: [môn 1, môn 2], questions: [{q, answers, correct,
## why, header, subject}]} – Công nghệ / Sinh học luôn có một tiết.
static func build(rng: RandomNumberGenerator) -> Dictionary:
	var names: Array = SUBJECTS.keys()
	var core: String = "Công nghệ" if rng.randf() < 0.5 else "Sinh học"
	names.erase(core)
	var other: String = String(names[rng.randi_range(0, names.size() - 1)])
	var periods: Array[String] = [core, other]
	var questions: Array = []
	for p in range(periods.size()):
		var pool: Array = (SUBJECTS[periods[p]] as Array).duplicate()
		_shuffle(pool, rng)
		for n in range(mini(PER_PERIOD, pool.size())):
			var question: Dictionary = pool[n]
			var answers: Array = (question["a"] as Array).duplicate()
			var correct: String = answers[0]
			_shuffle(answers, rng)
			questions.append({"q": question["q"], "answers": answers, "correct": answers.find(correct),
				"why": question["why"], "header": "Tiết %d · %s" % [p + 1, periods[p]], "subject": periods[p],
				"praise": PRAISE[questions.size() % PRAISE.size()]})
	return {"subjects": periods, "questions": questions}


## Hai tiết; trả về {"right", "total", "subjects": [tên môn], "cancelled": false}.
func run(dialog: DialogBox, rng: RandomNumberGenerator) -> Dictionary:
	var names: Array = SUBJECTS.keys()
	var core: String = "Công nghệ" if rng.randf() < 0.5 else "Sinh học"
	names.erase(core)
	var other: String = String(names[rng.randi_range(0, names.size() - 1)])
	var periods: Array[String] = [core, other]
	var right: int = 0
	var total: int = 0
	for p in range(periods.size()):
		var subject: String = periods[p]
		await dialog.say([[TEACHER, "Tiết %d: môn %s. Cả lớp trật tự!" % [p + 1, subject]]])
		var pool: Array = (SUBJECTS[subject] as Array).duplicate()
		_shuffle(pool, rng)
		for n in range(mini(PER_PERIOD, pool.size())):
			var question: Dictionary = pool[n]
			var answers: Array = (question["a"] as Array).duplicate()
			var correct: String = answers[0]
			_shuffle(answers, rng)
			current_answer = answers.find(correct)
			total += 1
			var pick: int = await dialog.choose(TEACHER, question["q"], answers)
			if pick == current_answer:
				right += 1
				await dialog.say([[TEACHER, "%s %s" % [PRAISE[(right - 1) % PRAISE.size()], question["why"]]]])
			else:
				await dialog.say([[TEACHER, "Sai rồi em. Đáp án: %s. %s" % [correct, question["why"]]]])
	current_answer = -1
	return {"right": right, "total": total, "subjects": periods, "cancelled": false}


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
