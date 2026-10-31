module DocumentText
  # Native text of each page of a PDF, with pdf-reader (docs/adr/0016). The
  # file is untrusted: a page whose text layer cannot be decoded comes back
  # as nil — the caller sends it to OCR — and a file that cannot be opened
  # at all is a failure with an error code, never an exception carrying the
  # parser's message.
  module PdfText
    ENGINE = "pdf-reader #{Gem.loaded_specs.fetch("pdf-reader").version}".freeze

    module_function

    # success([String or nil, ...]) | failure("unreadable_file" | "encrypted_pdf" | "too_many_pages")
    def call(path)
      reader = PDF::Reader.new(path)
      count = reader.page_count
      return ServiceResult.failure("unreadable_file") if count < 1
      return ServiceResult.failure("too_many_pages") if count > DocumentTextExtraction::MAX_PAGES

      ServiceResult.success(reader.pages.map { |page| page_text(page) })
    rescue PDF::Reader::EncryptedPDFError
      ServiceResult.failure("encrypted_pdf")
    rescue StandardError
      # pdf-reader raises a range of errors on malformed input
      # (MalformedPDFError, UnsupportedFeatureError, but also TypeError,
      # NoMethodError, ...): for an untrusted file they all mean "unreadable".
      ServiceResult.failure("unreadable_file")
    end

    def page_text(page)
      page.text
    rescue StandardError
      nil
    end
  end
end
