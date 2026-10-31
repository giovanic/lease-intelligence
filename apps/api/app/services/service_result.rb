# Return value of service objects (docs/architecture/backend.md): expected
# business outcomes are a failure result with an error code, not an
# exception.
ServiceResult = Data.define(:value, :error) do
  def self.success(value = nil)
    new(value: value, error: nil)
  end

  def self.failure(error)
    new(value: nil, error: error)
  end

  def success?
    error.nil?
  end

  def failure?
    !success?
  end
end
