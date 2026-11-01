# Explicit JSON shape for one page of extracted text (docs/adr/0016,
# docs/adr/0019): contract content, served only to members of the tenant
# for the review screen (evidence offsets point into `text`).
class DocumentTextPageSerializer
  def initialize(page)
    @page = page
  end

  def as_json(*)
    { page_number: @page.page_number, source: @page.source, text: @page.text }
  end
end
