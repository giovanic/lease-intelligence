module Documents
  # Validates an uploaded file and computes what a DocumentVersion records
  # about it (docs/adr/0015 "accepted files"). The type comes from the
  # file's leading bytes — the extension and the client's declared
  # Content-Type are ignored. SHA-256 (duplicate detection, integrity) and
  # MD5 (the storage service's upload integrity check) are computed in one
  # streaming pass.
  #
  # Returns an Upload on success, an error message for the `file` field on
  # failure.
  class InspectUpload
    SIGNATURES = {
      "application/pdf" => [ "%PDF-".b ],
      "image/png" => [ "\x89PNG\r\n\x1A\n".b ],
      "image/jpeg" => [ "\xFF\xD8\xFF".b ],
      "image/tiff" => [ "II*\x00".b, "MM\x00*".b ]
    }.freeze
    SIGNATURE_LENGTH = SIGNATURES.values.flatten.map(&:bytesize).max
    CHUNK_SIZE = 1.megabyte
    MAX_FILENAME_LENGTH = 255

    Upload = Data.define(:io, :original_filename, :content_type, :byte_size, :sha256, :md5_base64)

    def self.call(file)
      return ServiceResult.failure("can't be blank") unless uploaded_file?(file)

      byte_size = file.size
      return ServiceResult.failure("is empty") if byte_size.zero?
      return ServiceResult.failure("is too large (maximum is 50 MB)") if byte_size > DocumentVersion::MAX_BYTE_SIZE

      content_type = detect_content_type(file)
      return ServiceResult.failure("must be a PDF, JPEG, PNG or TIFF file") unless content_type

      sha256, md5 = digests(file)
      ServiceResult.success(
        Upload.new(io: file, original_filename: sanitize_filename(file.original_filename), content_type: content_type,
          byte_size: byte_size, sha256: sha256.hexdigest, md5_base64: md5.base64digest)
      )
    end

    def self.uploaded_file?(file)
      %i[read rewind size original_filename].all? { |method| file.respond_to?(method) }
    end

    def self.detect_content_type(file)
      file.rewind
      head = file.read(SIGNATURE_LENGTH).to_s.b
      file.rewind
      SIGNATURES.find { |_type, signatures| signatures.any? { |signature| head.start_with?(signature) } }&.first
    end

    def self.digests(file)
      sha256 = Digest::SHA256.new
      md5 = OpenSSL::Digest.new("MD5")
      file.rewind
      while (chunk = file.read(CHUNK_SIZE))
        sha256.update(chunk)
        md5.update(chunk)
      end
      file.rewind
      [ sha256, md5 ]
    end

    # Keeps only the base name the user's machine reported, as valid UTF-8
    # without control characters; it is shown back to users, never used as
    # a storage path (the key is derived from ids).
    def self.sanitize_filename(name)
      # Control characters go first: File.basename raises on a null byte.
      base = name.to_s.dup.force_encoding(Encoding::UTF_8).scrub("").gsub(/[[:cntrl:]]/, "").tr("\\", "/")
      base = File.basename(base).strip
      base = "document" if base.empty? || %w[. ..].include?(base)
      base[0, MAX_FILENAME_LENGTH]
    end

    private_class_method :uploaded_file?, :detect_content_type, :digests, :sanitize_filename
  end
end
