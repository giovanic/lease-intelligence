# The internal OCR provider interface (docs/adr/0008-ocr-provider-abstraction.md,
# docs/adr/0016-document-text-extraction.md). Pipeline code depends on this
# module only, never on a vendor tool or SDK.
#
# A provider responds to:
#
#   engine -> String
#     Engine name and version, recorded on the DocumentTextExtraction
#     (e.g. "tesseract 5.3.4 (por)").
#   recognize(path:, content_type:, page_numbers: nil) -> [Ocr::Page]
#     `path` is a local file of one of DocumentVersion::CONTENT_TYPES. For a
#     PDF, `page_numbers` (1-based) are the pages to recognize; for an image
#     it is ignored and every frame (a multi-page TIFF has several) is
#     returned, numbered from 1.
#
# Failures raise one of the errors below, never a vendor error. Their
# messages are fixed strings: never put file content or vendor output in
# them, they end up in logs.
module Ocr
  Page = Data.define(:number, :text)

  class Error < StandardError; end
  # A page (or the whole file) took longer than the provider's limit.
  class TimeoutError < Error; end
  # The provider could not read the file (corrupt, unsupported, encrypted).
  class UnreadableFileError < Error; end
  # The provider is not installed, not reachable or failed to run.
  class UnavailableError < Error; end

  module_function

  # The provider the pipeline uses. Tesseract, run locally, is the only
  # real one (ADR-0016); specs pass a fake one explicitly.
  def provider
    @provider ||= TesseractProvider.new
  end
end
