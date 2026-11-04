class_name InputSource
extends RefCounted

# Pure input-source interface. Local event capture is handled by LocalInputCapture (a Node adapter).
func is_ready(_tick: int) -> bool:
	return true


func sample(_tick: int) -> InputFrame:
	push_error("InputSource.sample() is abstract; use a concrete input source.")
	return null
