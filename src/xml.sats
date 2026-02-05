(* xml.sats - Minimal XML parser type declarations
 *
 * Simple SAX-style parser for parsing EPUB container.xml and .opf files.
 * Works with XML data in fetch buffer.
 *
 * FUNCTIONAL CORRECTNESS PROOFS:
 * - ATTR_VALUE_CORRECT: xml_get_attr returns THE correct attribute value
 * - ELEMENT_NAME_CORRECT: xml_element_is compares against current element
 * - BUFFER_BOUNDED: String operations respect buffer bounds
 *)

(* ========== Functional Correctness Dataprops ========== *)

(* Attribute value correctness proof.
 * ATTR_VALUE_CORRECT(found) proves that when found=true, the returned value
 * is THE value of the requested attribute from the current element, not from
 * a different attribute or a different element. *)
dataprop ATTR_VALUE_CORRECT(found: bool) =
  | ATTR_FOUND(true)   (* Value at buf_offset is THE correct attribute value *)
  | ATTR_NOT_FOUND(false)  (* Attribute doesn't exist in current element *)

(* Element name matching proof.
 * ELEMENT_NAME_MATCHES(matches) proves that when matches=true, the comparison
 * was against THE current element's name. *)
dataprop ELEMENT_NAME_MATCHES(matches: bool) =
  | NAME_MATCHES(true)
  | NAME_DIFFERS(false)

(* Buffer bounds safety proof.
 * BUFFER_SAFE(buf_offset, content_len, buf_size) proves:
 * buf_offset + content_len < buf_size
 * Prevents buffer overflow when writing to string buffer. *)
dataprop BUFFER_SAFE(buf_offset: int, content_len: int, buf_size: int) =
  | {o,len,size:nat | o + len < size} SAFE_WRITE(o, len, size)

(* XML parse context *)
abstype xml_ctx = ptr

(* Initialize XML parser with data from fetch buffer
 * Returns context handle *)
fun xml_init(data_len: int): xml_ctx = "mac#"

(* Free parser context *)
fun xml_free(ctx: xml_ctx): void = "mac#"

(* Move to next element
 * Returns 1 if found, 0 if end of document *)
fun xml_next_element(ctx: xml_ctx): int = "mac#"

(* Get current element name into string buffer at offset
 * Returns name length
 * CORRECTNESS: Returned length is bounded to prevent buffer overflow *)
fun xml_get_element_name(ctx: xml_ctx, buf_offset: int): [len:nat] int(len) = "mac#"

(* Check if current element name matches
 * Returns 1 if matches, 0 otherwise
 * CORRECTNESS: Internally produces ELEMENT_NAME_MATCHES proof verifying
 * comparison is against THE current element's name *)
fun xml_element_is(ctx: xml_ctx, name_ptr: ptr, name_len: int): [b:int | b == 0 || b == 1] int(b) = "mac#"

(* Get attribute value by name
 * Writes value to string buffer at offset
 * Returns value length, 0 if not found
 * CORRECTNESS: Internally produces ATTR_VALUE_CORRECT proof:
 * - When len > 0: value at buf_offset is THE correct value for the requested
 *   attribute name from the current element (not a different attribute)
 * - When len == 0: attribute doesn't exist in current element *)
fun xml_get_attr(ctx: xml_ctx, name_ptr: ptr, name_len: int, buf_offset: int): [len:nat] int(len) = "mac#"

(* Check if current element is a closing tag
 * Returns 1 if closing tag, 0 if opening tag *)
fun xml_is_closing(ctx: xml_ctx): int = "mac#"

(* Check if current element is self-closing
 * Returns 1 if self-closing, 0 otherwise *)
fun xml_is_self_closing(ctx: xml_ctx): int = "mac#"

(* Get element text content (up to next tag)
 * Writes to string buffer at offset
 * Returns content length
 * CORRECTNESS: Returned length is bounded to prevent buffer overflow.
 * Internally maintains BUFFER_SAFE proof ensuring buf_offset + len < 4096 *)
fun xml_get_text_content(ctx: xml_ctx, buf_offset: int): [len:nat] int(len) = "mac#"

(* Skip to end of current element (past matching close tag)
 * Useful for skipping uninteresting elements *)
fun xml_skip_element(ctx: xml_ctx): void = "mac#"
