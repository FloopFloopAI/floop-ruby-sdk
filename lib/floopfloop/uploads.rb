# frozen_string_literal: true

module FloopFloop
  class Uploads
    MAX_UPLOAD_BYTES = 5 * 1024 * 1024

    EXT_TO_MIME = {
      ".png"  => "image/png",
      ".jpg"  => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".gif"  => "image/gif",
      ".svg"  => "image/svg+xml",
      ".webp" => "image/webp",
      ".ico"  => "image/x-icon",
      ".pdf"  => "application/pdf",
      ".txt"  => "text/plain",
      ".csv"  => "text/csv",
      ".doc"  => "application/msword",
      ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    }.freeze

    def initialize(client)
      @client = client
    end

    # Presign an upload slot, PUT the bytes directly to S3, return the
    # UploadedAttachment hash { "key" => ..., "fileName" => ..., ... }
    # ready to drop into projects.refine's :attachments array.
    #
    # @param file_name [String] name the upload will be saved as.
    # @param bytes [String] binary payload (set `.force_encoding("BINARY")`
    #   if you're passing raw bytes).
    # @param file_type [String, nil] MIME override; guessed from file_name
    #   when absent.
    # @return [Hash] attachment reference for projects.refine.
    def create(file_name:, bytes:, file_type: nil)
      raise_validation("file_name is required") if file_name.nil? || file_name.empty?
      raise_validation("bytes is required")     if bytes.nil?

      resolved_type = file_type || guess_mime_type(file_name)
      raise_validation(
        "unsupported file type for #{file_name}. Allowed: png, jpg, gif, svg, webp, ico, pdf, txt, csv, doc, docx.",
      ) if resolved_type.nil? || !EXT_TO_MIME.value?(resolved_type)

      size = bytes.bytesize
      raise_validation(
        "#{file_name} is #{format('%.1f', size / 1024.0 / 1024.0)} MB — the upload limit is #{MAX_UPLOAD_BYTES / 1024 / 1024} MB.",
      ) if size > MAX_UPLOAD_BYTES

      presign = @client.request(
        "POST",
        "/api/v1/uploads",
        body: { fileName: file_name, fileType: resolved_type, fileSize: size },
      )

      @client.raw_put(presign.fetch("uploadUrl"), bytes, content_type: resolved_type)

      {
        "key"      => presign.fetch("key"),
        "fileName" => file_name,
        "fileType" => resolved_type,
        "fileSize" => size,
      }
    end

    # Convenience: read a local file off disk and upload it. Typical
    # Ruby app use case since host-side code usually has filesystem
    # access (unlike the MCP where binary payloads can't cross stdio).
    def create_from_path(file_path, file_type: nil)
      raise_validation("file_path is required") if file_path.nil? || file_path.empty?
      raise FloopFloop::Error.new(code: "VALIDATION_ERROR", message: "uploads: #{file_path} does not exist", status: 0) unless File.exist?(file_path)
      raise FloopFloop::Error.new(code: "VALIDATION_ERROR", message: "uploads: #{file_path} is not a regular file", status: 0) unless File.file?(file_path)

      bytes = File.binread(file_path)
      create(file_name: File.basename(file_path), bytes: bytes, file_type: file_type)
    end

    def self.guess_mime_type(file_name)
      ext = File.extname(file_name.to_s).downcase
      EXT_TO_MIME[ext]
    end

    private

    def guess_mime_type(file_name)
      self.class.guess_mime_type(file_name)
    end

    def raise_validation(message)
      raise FloopFloop::Error.new(code: "VALIDATION_ERROR", message: "uploads: #{message}", status: 0)
    end
  end
end
