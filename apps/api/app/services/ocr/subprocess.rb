require "open3"

module Ocr
  # Runs an OCR/rasterization binary safely (docs/adr/0016 "Security
  # implications"): an argument array, never a shell string, so nothing in
  # a path can be interpreted; its own process group, so a timeout kills
  # it together with any child it started. Only generated temp paths go in
  # `argv` — never document content.
  #
  # The binaries parse hostile files, so a parser bug is assumed
  # exploitable: the child gets a minimal environment (none of the worker's
  # secrets — RAILS_MASTER_KEY, database and storage credentials) and a cap
  # on its address space, so a decompression bomb dies alone instead of
  # starving the machine.
  module Subprocess
    Outcome = Data.define(:stdout, :stderr, :status)

    # Variables the binaries may need; everything else is dropped.
    INHERITED_VARIABLES = %w[PATH TMPDIR TESSDATA_PREFIX].freeze
    # OpenMP inside Tesseract would otherwise start one thread per core in
    # each Sidekiq thread; Tesseract expects the C locale.
    FIXED_VARIABLES = { "OMP_THREAD_LIMIT" => "1", "LC_ALL" => "C" }.freeze
    MAX_ADDRESS_SPACE = 3 * 1024**3 # bytes

    module_function

    def run(*argv, timeout:)
      environment = ENV.to_h.slice(*INHERITED_VARIABLES).merge(FIXED_VARIABLES)
      options = { pgroup: true, unsetenv_others: true, rlimit_as: MAX_ADDRESS_SPACE }
      Open3.popen3(environment, *argv, **options) do |stdin, stdout, stderr, wait|
        stdin.close
        out = Thread.new { stdout.read }
        err = Thread.new { stderr.read }

        unless wait.join(timeout)
          kill_group(wait.pid)
          wait.join
          raise TimeoutError, "#{File.basename(argv.first)} timed out after #{timeout}s"
        end

        Outcome.new(stdout: out.value, stderr: err.value, status: wait.value)
      end
    rescue SystemCallError
      # ENOENT (binary missing), EACCES, ...: the engine cannot run here.
      raise UnavailableError, "#{File.basename(argv.first)} could not be started"
    end

    def kill_group(pid)
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
      nil # already gone
    end
  end
end
