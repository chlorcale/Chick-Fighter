extends RefCounted

## Trường TH Bình Kê: cô Hạnh đố 3 câu (chọn ngẫu nhiên trong bộ câu hỏi) bằng DialogBox.choose.
## Đáp án đúng luôn là phương án đầu tiên trong QUESTIONS; thứ tự hiển thị được xáo.
## current_answer: chỉ số đáp án đúng của câu đang hỏi (test đọc để trả lời).

const TEACHER: String = "Cô Hạnh"
const COUNT: int = 3
const QUESTIONS: Array[Dictionary] = [
	{"q": "Chợ nổi Cái Răng nổi tiếng nằm ở đâu?",
		"a": ["Cần Thơ", "Hà Nội", "Đà Lạt", "Huế"],
		"why": "Chợ nổi Cái Răng ở Cần Thơ, ghe xuồng họp chợ trên sông từ sáng sớm."},
	{"q": "Ghe trên chợ nổi treo trái cây lên một cây sào cho khách thấy. Cây sào đó kêu là gì?",
		"a": ["Cây bẹo", "Cây nêu", "Cột cờ", "Cần câu"],
		"why": "Cây bẹo: ghe bán gì thì treo nấy, khỏi cần rao."},
	{"q": "Một ký cá tra 40.000đ. Mua 3 ký hết bao nhiêu tiền?",
		"a": ["120.000đ", "100.000đ", "140.000đ", "43.000đ"],
		"why": "40.000 × 3 = 120.000đ."},
	{"q": "Hai bó lúa, mỗi bó 12 bông, thêm 6 bông lẻ. Tổng cộng mấy bông?",
		"a": ["30 bông", "24 bông", "26 bông", "32 bông"],
		"why": "12 × 2 = 24, cộng 6 là 30."},
	{"q": "Tám con gà trống, mỗi con hai cái cựa. Hỏi có bao nhiêu cái cựa?",
		"a": ["16 cái", "10 cái", "18 cái", "82 cái"],
		"why": "8 × 2 = 16. Gà chín cựa thì… chuyện khác à nghen!"},
	{"q": "Vua Hùng kén rể, đòi voi chín ngà, gà chín cựa và ngựa… gì?",
		"a": ["Chín hồng mao", "Chín cái đuôi", "Chín cái móng", "Chín màu lông"],
		"why": "Voi chín ngà, gà chín cựa, ngựa chín hồng mao – sính lễ trong truyện Sơn Tinh Thủy Tinh."},
	{"q": "Ông nội hay dặn: gà hay là gà biết làm gì?",
		"a": ["Biết đọc đối thủ", "Gáy to nhứt xóm", "Ăn được nhiều lúa", "Chạy lẹ nhứt"],
		"why": "Biết lúc nào tới, lúc nào lui – đó mới là gà hay."},
	{"q": "Lúc đá gà, muốn đỡ đòn thì giữ phím hướng nào?",
		"a": ["Giữ lùi, ngược phía đối thủ", "Giữ tới, sát đối thủ", "Nhảy lên cho né", "Hổng cần giữ gì"],
		"why": "Giữ lùi để đỡ; đòn thấp thì cúi xuống mà đỡ."},
	{"q": "Thẻ Mai Rùa trong trận đá gà có công dụng gì?",
		"a": ["Giảm sát thương nhận vào", "Tăng sức đá", "Đá đẩy lùi xa hơn", "Hồi đầy máu"],
		"why": "Mai Rùa giảm 25% sát thương trong 5 giây, chịu đòn chắc hơn."},
	{"q": "Sông Cửu Long – “chín con rồng” – là vì đổ ra biển bằng mấy cửa?",
		"a": ["Chín cửa", "Năm cửa", "Bảy cửa", "Mười hai cửa"],
		"why": "Chín cửa sông nên kêu là Cửu Long."},
	{"q": "Cây cầu bắc bằng thân tre, đi phải vịn tay cho khỏi té, kêu là cầu gì?",
		"a": ["Cầu khỉ", "Cầu treo", "Cầu tàu", "Cầu vồng"],
		"why": "Cầu khỉ – ở kênh xóm mình cũng có một cây đó."},
	{"q": "Mùa nước nổi ở miền Tây thường rơi vào khoảng nào?",
		"a": ["Khoảng tháng 8 tới tháng 11", "Tháng Giêng", "Quanh Tết", "Tháng Tư"],
		"why": "Nước nổi về thì có cá linh, bông điên điển đó con."},
	{"q": "Bánh xèo miền Tây cuốn với gì ăn mới đúng điệu?",
		"a": ["Rau sống, chấm nước mắm chua ngọt", "Chấm sữa đặc", "Chấm tương ớt Tây", "Ăn không vậy thôi"],
		"why": "Cuốn cải bẹ xanh, lá lốt, rau thơm rồi chấm nước mắm – ngon hết sẩy."},
]
const PRAISE: Array[String] = ["Giỏi quá! Đúng rồi con.", "Chính xác! Cô cho con một điểm mười.", "Đúng rồi, nhớ bài kỹ ghê ha!"]

var current_answer: int = -1


## Hỏi COUNT câu; trả về {"right": số câu đúng, "total": COUNT, "cancelled": false}.
func run(dialog: DialogBox, rng: RandomNumberGenerator) -> Dictionary:
	var order: Array = range(QUESTIONS.size())
	_shuffle(order, rng)
	var right: int = 0
	for n in range(COUNT):
		var question: Dictionary = QUESTIONS[order[n]]
		var answers: Array = (question["a"] as Array).duplicate()
		var correct: String = answers[0]
		_shuffle(answers, rng)
		current_answer = answers.find(correct)
		var pick: int = await dialog.choose(TEACHER, "Câu %d/%d: %s" % [n + 1, COUNT, question["q"]], answers)
		if pick == current_answer:
			right += 1
			await dialog.say([[TEACHER, "%s %s" % [PRAISE[n % PRAISE.size()], question["why"]]]])
		else:
			await dialog.say([[TEACHER, "Chưa đúng rồi con. Đáp án là: %s. %s" % [correct, question["why"]]]])
	current_answer = -1
	return {"right": right, "total": COUNT, "cancelled": false}


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
