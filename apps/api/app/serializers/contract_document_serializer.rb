# Explicit JSON shape for a ContractDocument with its versions, newest
# first. Versions are inlined: a document gets a new one only when a file
# is replaced, so the list stays short (documents themselves are paginated).
class ContractDocumentSerializer
  def initialize(document)
    @document = document
  end

  def as_json(*)
    {
      id: @document.id,
      lease_id: @document.lease_id,
      kind: @document.kind,
      title: @document.title,
      versions: @document.versions.map { |version| DocumentVersionSerializer.new(version).as_json },
      created_at: @document.created_at,
      updated_at: @document.updated_at
    }
  end
end
