(* xml.sats - Minimal XML parser type declarations
 *
 * Simple SAX-style parser for parsing EPUB container.xml and .opf files.
 * Works with XML data in fetch buffer.
 *)

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
 * Returns name length *)
fun xml_get_element_name(ctx: xml_ctx, buf_offset: int): int = "mac#"

(* Check if current element name matches
 * Returns 1 if matches, 0 otherwise *)
fun xml_element_is(ctx: xml_ctx, name_ptr: ptr, name_len: int): int = "mac#"

(* Get attribute value by name
 * Writes value to string buffer at offset
 * Returns value length, 0 if not found *)
fun xml_get_attr(ctx: xml_ctx, name_ptr: ptr, name_len: int, buf_offset: int): int = "mac#"

(* Check if current element is a closing tag
 * Returns 1 if closing tag, 0 if opening tag *)
fun xml_is_closing(ctx: xml_ctx): int = "mac#"

(* Check if current element is self-closing
 * Returns 1 if self-closing, 0 otherwise *)
fun xml_is_self_closing(ctx: xml_ctx): int = "mac#"

(* Get element text content (up to next tag)
 * Writes to string buffer at offset
 * Returns content length *)
fun xml_get_text_content(ctx: xml_ctx, buf_offset: int): int = "mac#"

(* Skip to end of current element (past matching close tag)
 * Useful for skipping uninteresting elements *)
fun xml_skip_element(ctx: xml_ctx): void = "mac#"
