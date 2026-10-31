# The text of one page of a DocumentTextExtraction
# (docs/adr/0016-document-text-extraction.md), from the PDF itself
# (`native`) or from OCR (`ocr`). Contract content: never log it. Written
# once, by DocumentText::ProcessExtraction; the database rejects any UPDATE
# or DELETE (db/migrate/20261031220001_create_document_text_pages.rb), and
# `readonly?` makes ActiveRecord refuse before even trying.
class DocumentTextPage < ApplicationRecord
  belongs_to :tenant
  belongs_to :text_extraction, class_name: "DocumentTextExtraction", inverse_of: :pages

  # native: text layer of the PDF (pdf-reader); ocr: recognized from the
  # page image (Ocr provider).
  enum :source, { native: "native", ocr: "ocr" }, validate: true

  validates :page_number, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :text, exclusion: { in: [ nil ], message: "can't be nil" }

  def readonly?
    persisted? || super
  end
end
