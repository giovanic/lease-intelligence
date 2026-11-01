module FieldExtraction
  # First step of ExtractContractFieldsJob, in the tenant context: marks the
  # run `running` and loads the pages of the exact text extraction it reads.
  # A finished run (duplicate delivery, or closed as abandoned) is a
  # failure, and the job stops there. A `running` one is resumed: nothing
  # was stored yet, since fields are written only by RecordOutcome.
  #
  # The page texts leave the transaction as plain values for the provider
  # call; they are contract content — never log them or pass them to a job.
  #
  # success([Page]) | failure("finished")
  class StartRun
    Page = Data.define(:id, :number, :text)

    def self.call(run_id)
      run = ExtractionRun.lock.find(run_id)
      return ServiceResult.failure("finished") if run.finished?

      run.update!(status: :running, started_at: run.started_at || Time.current)
      pages = run.text_extraction.pages.map { |page| Page.new(id: page.id, number: page.page_number, text: page.text) }
      ServiceResult.success(pages)
    end
  end
end
