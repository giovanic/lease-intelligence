require "tmpdir"

module Ocr
  # OCR with Tesseract run locally (docs/adr/0016-document-text-extraction.md):
  # contract content never leaves our infrastructure. Needs the
  # `tesseract-ocr`, `tesseract-ocr-por` and `poppler-utils` packages
  # (apps/api/Dockerfile, CI). Tesseract does not read PDF, so a PDF page is
  # first rasterized with `pdftoppm` — Ghostscript/ImageMagick are not used
  # (see the ADR's alternatives).
  class TesseractProvider
    LANGUAGE = "por".freeze
    # Longest side of a rendered PDF page, in pixels: an A4 page at 300 DPI.
    # A size cap rather than a DPI, so a page with a huge MediaBox cannot
    # become a multi-gigapixel image.
    MAX_PAGE_PIXELS = 3508
    RASTERIZE_TIMEOUT = 60   # seconds per PDF page
    RECOGNIZE_TIMEOUT = 120  # seconds per page image
    # An image file is recognized in one call; a multi-page TIFF has every
    # frame in it, so its limit covers more than one page.
    IMAGE_FILE_TIMEOUT = 600
    PAGE_SEPARATOR = "\f".freeze

    # Also proves the engine can run here, with the Portuguese model: called
    # before any page is recognized, so a missing package is reported as
    # `ocr_unavailable`, not as an unreadable file.
    def engine
      @engine ||= begin
        ensure_language!
        "#{tesseract_version} (#{LANGUAGE})"
      end
    end

    def recognize(path:, content_type:, page_numbers: nil)
      if content_type == "application/pdf"
        recognize_pdf_pages(path, page_numbers)
      else
        recognize_image(path)
      end
    end

    private

    def recognize_pdf_pages(path, page_numbers)
      Dir.mktmpdir("ocr") do |dir|
        page_numbers.map do |number|
          image = rasterize(path, number, File.join(dir, "page-#{number}"))
          Page.new(number: number, text: tesseract(image, timeout: RECOGNIZE_TIMEOUT).delete_suffix(PAGE_SEPARATOR))
        end
      end
    end

    def recognize_image(path)
      output = tesseract(path, timeout: IMAGE_FILE_TIMEOUT)
      # Tesseract ends every page with a form feed.
      texts = output.split(PAGE_SEPARATOR, -1)
      texts.pop if output.end_with?(PAGE_SEPARATOR)
      texts = [ "" ] if texts.empty?
      texts.each_with_index.map { |text, index| Page.new(number: index + 1, text: text) }
    end

    # -singlefile writes exactly "<prefix>.png".
    def rasterize(pdf_path, number, prefix)
      outcome = Subprocess.run(
        "pdftoppm", "-f", number.to_s, "-l", number.to_s, "-scale-to", MAX_PAGE_PIXELS.to_s, "-gray", "-png", "-singlefile",
        pdf_path, prefix, timeout: RASTERIZE_TIMEOUT
      )
      image = "#{prefix}.png"
      raise UnreadableFileError, "pdftoppm could not render page #{number}" unless outcome.status.success? && File.file?(image)

      image
    end

    def tesseract(image_path, timeout:)
      outcome = Subprocess.run("tesseract", image_path, "stdout", "-l", LANGUAGE, timeout: timeout)
      raise UnreadableFileError, "tesseract could not read the image" unless outcome.status.success?

      outcome.stdout
    end

    def ensure_language!
      outcome = Subprocess.run("tesseract", "--list-langs", timeout: 10)
      languages = "#{outcome.stdout}\n#{outcome.stderr}".lines.map(&:strip)
      raise UnavailableError, "tesseract has no #{LANGUAGE} model" unless outcome.status.success? && languages.include?(LANGUAGE)
    end

    def tesseract_version
      outcome = Subprocess.run("tesseract", "--version", timeout: 10)
      raise UnavailableError, "tesseract --version failed" unless outcome.status.success?

      # Older releases print the version on stderr.
      (outcome.stdout.presence || outcome.stderr).lines.first.to_s.strip.presence ||
        raise(UnavailableError, "tesseract --version printed nothing")
    end
  end
end
