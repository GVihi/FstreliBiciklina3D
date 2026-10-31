extends RefCounted
# Reads api_key.bin (roadmap V4.1): the game's API address and key as an exported build carries them.
# tools/build_release.py writes the file from the build machine's environment just before the export and deletes it
# afterwards (tools/api_key_file.py has the writer and the full description of the format); the export preset
# includes it. The file is untracked (`api_key.*` in .gitignore).
# THIS IS OBFUSCATION, NOT PROTECTION: the key is not a readable string in the exe, a script or project.godot, but
# whoever runs the game can get it out, and the server never trusts the key alone (docs/WEBSITE_API.md).
# Format, version 1: "FB3K", the version byte 1, a 16 byte nonce, the JSON text {"base_url": "...", "key": "..."} XOR a
# key stream of SHA-256(SALT + nonce + block number as 4 bytes, big endian), and an 8 byte check (the first 8 bytes of
# SHA-256(SALT + nonce + text)). A damaged file is never half used: decode() gives {} and load_file() says "damaged".
# It never prints anything, least of all a value. Check: `python tools/run_checks.py web_api`.

const FILE = "res://api_key.bin"
const MAGIC = "FB3K"
const FORMAT_VERSION = 1
const NONCE_LENGTH = 16
const MAC_LENGTH = 8
const SALT = "fb3d-api-key-file-v1"
const BLOCK_LENGTH = 32
const MIN_LENGTH = 4 + 1 + 16 + 2 + 8
const MAX_FILE = 2048
const SOURCE_NONE = "no file"
const SOURCE_FILE = "file"
const SOURCE_DAMAGED = "damaged"


# {"base_url", "key", "source"}: "source" is "no file" (an editor run, a build made without a key), "file" or "damaged"
# (then both values are empty). Never an error.
static func load_file(path: String = FILE) -> Dictionary:
	var out = {"base_url": "", "key": "", "source": SOURCE_NONE}
	if not FileAccess.file_exists(path):
		return out
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		out["source"] = SOURCE_DAMAGED
		return out
	if file.get_length() > MAX_FILE:
		file.close()
		out["source"] = SOURCE_DAMAGED
		return out
	var bytes = file.get_buffer(file.get_length())
	file.close()
	var values = decode(bytes)
	if values.is_empty():
		out["source"] = SOURCE_DAMAGED
		return out
	out["base_url"] = str(values["base_url"])
	out["key"] = str(values["key"])
	out["source"] = SOURCE_FILE
	return out


# {"base_url", "key"} from the bytes of a file, or {} when the file is damaged in any way.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < MIN_LENGTH or bytes.size() > MAX_FILE:
		return {}
	var magic = MAGIC.to_utf8_buffer()
	for i in range(magic.size()):
		if bytes[i] != magic[i]:
			return {}
	if bytes[magic.size()] != FORMAT_VERSION:
		return {}
	var header = magic.size() + 1 + NONCE_LENGTH
	var nonce = bytes.slice(magic.size() + 1, header)
	var cipher = bytes.slice(header, bytes.size() - MAC_LENGTH)
	var mac = bytes.slice(bytes.size() - MAC_LENGTH, bytes.size())
	var plain = _xor(cipher, nonce)
	var expected = _sha256(SALT.to_utf8_buffer() + nonce + plain).slice(0, MAC_LENGTH)
	if expected != mac:
		return {}
	var json = JSON.new()
	if json.parse(plain.get_string_from_utf8()) != OK:
		return {}
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	if typeof(data.get("base_url")) != TYPE_STRING or typeof(data.get("key")) != TYPE_STRING:
		return {}
	return {"base_url": data["base_url"], "key": data["key"]}


static func _xor(cipher: PackedByteArray, nonce: PackedByteArray) -> PackedByteArray:
	var plain = PackedByteArray()
	var stream = PackedByteArray()
	var block = 0
	var salt = SALT.to_utf8_buffer()
	for i in range(cipher.size()):
		if i >= stream.size():
			var block_input = salt + nonce
			block_input.append((block >> 24) & 255)
			block_input.append((block >> 16) & 255)
			block_input.append((block >> 8) & 255)
			block_input.append(block & 255)
			stream.append_array(_sha256(block_input))
			block += 1
		plain.append(cipher[i] ^ stream[i])
	return plain


static func _sha256(data: PackedByteArray) -> PackedByteArray:
	var context = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(data)
	return context.finish()
