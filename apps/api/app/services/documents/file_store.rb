module Documents
  # The single place that touches the storage service for contract files
  # (docs/adr/0015): Active Storage's service layer — Disk in development
  # and test, an S3-compatible service once infrastructure exists — without
  # Active Storage's blobs/attachments tables. Keys are built here so every
  # file of a tenant sits under that tenant's prefix.
  #
  # Any failure of the storage backend surfaces as FileStore::Error, which
  # the API answers with 503 (ApplicationController); a write in progress
  # rolls back with it.
  module FileStore
    class Error < StandardError; end

    module_function

    def key_for(tenant_id:, version_id:)
      "tenants/#{tenant_id}/document_versions/#{version_id}"
    end

    def upload(key, io, md5_base64:, content_type:)
      io.rewind
      service.upload(key, io, checksum: md5_base64, content_type: content_type)
    rescue StandardError => error
      # Only the class: the message may carry the key or backend details.
      raise Error, "storage upload failed (#{error.class})"
    end

    def download(key)
      service.download(key)
    rescue StandardError => error
      raise Error, "storage download failed (#{error.class})"
    end

    def service
      ActiveStorage::Blob.service
    end
  end
end
