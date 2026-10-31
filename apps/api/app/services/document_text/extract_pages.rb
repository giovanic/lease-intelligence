require "tmpdir"

module DocumentText
  # Reads a version's bytes and turns them into per-page text
  # (docs/adr/0016-document-text-extraction.md): native PDF text where the
  # page has it, OCR for the pages that don't and for images. No database
  # access — ExtractDocumentTextJob runs this outside any transaction, since
  # OCR can take minutes.
  #
  # success(Extracted) | failure(error code from DocumentTextExtraction::ERROR_CODES)
  class ExtractPages
    PageText = Data.define(:number, :source, :text)
    Extracted = Data.define(:pages, :native_engine, :ocr_engine)

    # A PDF page with less native text than this is treated as scanned.
    MIN_NATIVE_CHARACTERS = 20

    OCR_ERROR_CODES = {
      Ocr::TimeoutError => "timeout",
      Ocr::UnreadableFileError => "unreadable_file",
      Ocr::UnavailableError => "ocr_unavailable"
    }.freeze

    def self.call(storage_key:, content_type:, ocr:)
      new(content_type: content_type, ocr: ocr).call(storage_key)
    end

    def initialize(content_type:, ocr:)
      @content_type = content_type
      @ocr = ocr
    end

    def call(storage_key)
      Dir.mktmpdir("document-text") do |dir|
        path = File.join(dir, "source")
        File.binwrite(path, Documents::FileStore.download(storage_key))
        @content_type == "application/pdf" ? from_pdf(path) : from_image(path)
      end
    rescue Documents::FileStore::Error
      ServiceResult.failure("storage_unavailable")
    rescue Ocr::Error => error
      ServiceResult.failure(OCR_ERROR_CODES.fetch(error.class, "ocr_unavailable"))
    end

    private

    def from_pdf(path)
      native = PdfText.call(path)
      return native if native.failure?

      texts = native.value.map { |text| text && normalize(text) }
      scanned = texts.each_index.select { |index| sparse?(texts[index]) }.map { |index| index + 1 }
      recognized = scanned.any? ? recognize(path, scanned) : {}

      pages = texts.each_with_index.map do |text, index|
        number = index + 1
        recognized.key?(number) ? PageText.new(number, "ocr", recognized[number]) : PageText.new(number, "native", text)
      end
      ServiceResult.success(Extracted.new(pages: pages, native_engine: PdfText::ENGINE, ocr_engine: (@ocr.engine if scanned.any?)))
    end

    def from_image(path)
      engine = @ocr.engine
      pages = @ocr.recognize(path: path, content_type: @content_type)
      return ServiceResult.failure("too_many_pages") if pages.size > DocumentTextExtraction::MAX_PAGES

      check_numbers!(pages, (1..pages.size).to_a)
      pages = pages.map { |page| PageText.new(page.number, "ocr", normalize(page.text)) }
      ServiceResult.success(Extracted.new(pages: pages, native_engine: nil, ocr_engine: engine))
    end

    # { page number => text } for the scanned pages of a PDF.
    def recognize(path, numbers)
      @ocr.engine # fails fast (ocr_unavailable) before any page is rendered
      pages = @ocr.recognize(path: path, content_type: @content_type, page_numbers: numbers)
      check_numbers!(pages, numbers)
      pages.to_h { |page| [ page.number, normalize(page.text) ] }
    end

    # A provider that returns other pages than asked is a bug, not a
    # property of the file: raise, so the job retries and then records
    # internal_error, rather than store text under the wrong page.
    def check_numbers!(pages, expected)
      return if pages.map(&:number) == expected

      raise ArgumentError, "OCR provider returned #{pages.size} pages for #{expected.size} requested"
    end

    def sparse?(text)
      text.nil? || text.gsub(/[[:space:]]/, "").length < MIN_NATIVE_CHARACTERS
    end

    # Valid UTF-8 without NUL (PostgreSQL text rejects it), Unicode NFC,
    # no trailing blanks on lines. Evidence spans will point into this exact
    # string, so it is normalized once, here, before it is stored.
    def normalize(text)
      text.to_s.dup.force_encoding(Encoding::UTF_8).scrub("�").delete("\u0000")
        .unicode_normalize(:nfc).gsub(/\r\n?/, "\n").gsub(/[ \t]+$/, "").strip
    end
  end
end
