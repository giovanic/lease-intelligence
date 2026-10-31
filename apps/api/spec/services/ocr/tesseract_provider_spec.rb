require "rails_helper"

# The real OCR adapter (docs/adr/0016-document-text-extraction.md). Needs
# tesseract-ocr, tesseract-ocr-por and poppler-utils: CI installs them and
# these examples must run there; on a machine without them they are
# skipped with the reason (docs/runbooks/testing.md).
RSpec.describe "OCR adapter" do
  describe Ocr::Subprocess do
    it "returns stdout, stderr and status of the command" do
      outcome = described_class.run("sh", "-c", "printf out; printf err >&2; exit 3", timeout: 5)

      expect([ outcome.stdout, outcome.stderr, outcome.status.exitstatus ]).to eq([ "out", "err", 3 ])
    end

    it "passes arguments verbatim, without a shell" do
      outcome = described_class.run("printf", "%s", "$(touch /tmp/pwned); `id`", timeout: 5)

      expect(outcome.stdout).to eq("$(touch /tmp/pwned); `id`")
    end

    it "runs the binary without the worker's environment, only what it needs" do
      ENV["SECRET_FOR_SUBPROCESS_SPEC"] = "s3cr3t"
      outcome = described_class.run("sh", "-c", "env", timeout: 5)

      expect(outcome.stdout).not_to include("s3cr3t")
      expect(outcome.stdout).to include("OMP_THREAD_LIMIT=1", "LC_ALL=C", "PATH=")
    ensure
      ENV.delete("SECRET_FOR_SUBPROCESS_SPEC")
    end

    it "caps the binary's address space" do
      outcome = described_class.run("sh", "-c", "ulimit -v", timeout: 5)

      expect(outcome.stdout.strip).to eq((described_class::MAX_ADDRESS_SPACE / 1024).to_s)
    end

    it "kills the process group and raises TimeoutError past the limit" do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      expect { described_class.run("sh", "-c", "sleep 30 & sleep 30", timeout: 0.5) }
        .to raise_error(Ocr::TimeoutError, "sh timed out after 0.5s")
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
    end

    it "raises UnavailableError when the binary does not exist" do
      expect { described_class.run("no-such-ocr-binary", timeout: 5) }
        .to raise_error(Ocr::UnavailableError, "no-such-ocr-binary could not be started")
    end
  end

  describe Ocr::TesseractProvider do
    subject(:provider) { described_class.new }

    let(:binaries_present) do
      %w[tesseract pdftoppm].all? { |binary| system("command -v #{binary} > /dev/null 2>&1") }
    end

    before do
      next if binaries_present
      raise "tesseract/pdftoppm are required in CI (see .github/workflows/ci.yml)" if ENV["CI"]

      skip "tesseract-ocr, tesseract-ocr-por and poppler-utils are not installed"
    end

    it "reports the engine version and language" do
      expect(provider.engine).to match(/\Atesseract \d+\.\d+.* \(por\)\z/)
    end

    it "recognizes the requested pages of a PDF" do
      pdf = write_tempfile(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL", "ALUGUEL MENSAL" ]), ".pdf")

      pages = provider.recognize(path: pdf.path, content_type: "application/pdf", page_numbers: [ 2 ])

      expect(pages.map(&:number)).to eq([ 2 ])
      expect(pages.first.text).to include("ALUGUEL MENSAL")
    end

    it "recognizes an image" do
      pdf = write_tempfile(build_pdf([ "CONTRATO DE LOCACAO COMERCIAL" ]), ".pdf")
      prefix = File.join(Dir.mktmpdir, "page")
      Ocr::Subprocess.run("pdftoppm", "-r", "150", "-png", "-singlefile", pdf.path, prefix, timeout: 30)

      pages = provider.recognize(path: "#{prefix}.png", content_type: "image/png")

      expect(pages.map(&:number)).to eq([ 1 ])
      expect(pages.first.text).to include("CONTRATO DE LOCACAO")
    end

    it "raises UnreadableFileError for a file it cannot read" do
      garbage = write_tempfile("%PDF-1.4 not really".b, ".pdf")

      expect { provider.recognize(path: garbage.path, content_type: "application/pdf", page_numbers: [ 1 ]) }
        .to raise_error(Ocr::UnreadableFileError)
      expect { provider.recognize(path: garbage.path, content_type: "image/png") }
        .to raise_error(Ocr::UnreadableFileError)
    end
  end
end
