module FieldExtraction
  # First step of ExtractContractFieldsJob, in the tenant context: marks the
  # run `running` and loads the pages of the exact text extraction it reads.
  # A finished run (duplicate delivery, or closed as abandoned) is a
  # failure, and the job stops there. So is a run of an organization that
  # turned AI extraction off since it was queued: it is closed as
  # `ai_disabled` here, before any provider call (docs/adr/0018). A `running` one is resumed: nothing
  # was stored yet, since fields are written only by RecordOutcome.
  #
  # The page texts leave the transaction as plain values for the provider
  # call; they are contract content — never log them or pass them to a job.
  #
  # success([Page]) | failure("finished" | "disabled")
  class StartRun
    Page = Data.define(:id, :number, :text)

    def self.call(run_id)
      run = ExtractionRun.lock.find(run_id)
      return ServiceResult.failure("finished") if run.finished?
      return disable(run) unless run.tenant.ai_extraction_enabled?

      run.update!(status: :running, started_at: run.started_at || Time.current)
      pages = run.text_extraction.pages.map { |page| Page.new(id: page.id, number: page.page_number, text: page.text) }
      ServiceResult.success(pages)
    end

    def self.disable(run)
      run.update!(status: :failed, error_code: "ai_disabled", finished_at: Time.current)
      ServiceResult.failure("disabled")
    end
    private_class_method :disable
  end
end
