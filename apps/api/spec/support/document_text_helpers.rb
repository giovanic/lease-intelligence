# Fixtures for the text extraction specs (docs/adr/0016).
module DocumentTextHelpers
  # A minimal, valid PDF built in memory: each entry of `pages` is the text
  # drawn on that page (Helvetica, large enough for OCR), or nil for a page
  # with no text layer — what a scanned page looks like to pdf-reader.
  def build_pdf(pages)
    objects = [ "<< /Type /Catalog /Pages 2 0 R >>", nil, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>" ]
    kids = pages.map do |text|
      stream = text ? "BT /F1 24 Tf 40 700 Td (#{text}) Tj ET" : ""
      objects << "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
      objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] " \
                 "/Resources << /Font << /F1 3 0 R >> >> /Contents #{objects.size} 0 R >>"
      "#{objects.size} 0 R"
    end
    objects[1] = "<< /Type /Pages /Kids [#{kids.join(" ")}] /Count #{pages.size} >>"

    pdf = +"%PDF-1.4\n"
    offsets = objects.each_with_index.map do |body, index|
      offset = pdf.bytesize
      pdf << "#{index + 1} 0 obj\n#{body}\nendobj\n"
      offset
    end
    xref = pdf.bytesize
    pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
    pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    pdf.b
  end

  def write_tempfile(bytes, extension)
    file = Tempfile.new([ "document-text", extension ], binmode: true)
    file.write(bytes)
    file.flush
    file
  end

  # Stands in for an OCR provider (Ocr): returns `texts[page number]`, or
  # raises `error` if given. Records what it was asked.
  class FakeOcr
    attr_reader :requests

    def initialize(texts = {}, error: nil, image_pages: 1)
      @texts = texts
      @error = error
      @image_pages = image_pages
      @requests = []
    end

    def engine
      "fake-ocr 1.0"
    end

    def recognize(path:, content_type:, page_numbers: nil)
      @requests << { path: path, content_type: content_type, page_numbers: page_numbers }
      raise @error if @error

      numbers = page_numbers || (1..@image_pages).to_a
      numbers.map { |number| Ocr::Page.new(number: number, text: @texts.fetch(number, "texto ocr #{number}")) }
    end
  end
end

RSpec.configure do |config|
  config.include DocumentTextHelpers
end
