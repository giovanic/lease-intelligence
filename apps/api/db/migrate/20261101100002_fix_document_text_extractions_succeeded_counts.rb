# The original check let a `succeeded` extraction with a NULL count through:
# `NULL >= 0` is NULL, and a CHECK that evaluates to NULL passes. COALESCE
# makes a missing count a violation (the same fix ADR-0017's tables got).
class FixDocumentTextExtractionsSucceededCounts < ActiveRecord::Migration[8.1]
  NAME = "document_text_extractions_succeeded_counts".freeze
  OLD = "status <> 'succeeded' OR (page_count >= 1 AND native_page_count >= 0 AND ocr_page_count >= 0 " \
    "AND native_page_count + ocr_page_count = page_count AND finished_at IS NOT NULL)".freeze
  NEW = "status <> 'succeeded' OR (COALESCE(page_count >= 1 AND native_page_count >= 0 AND ocr_page_count >= 0 " \
    "AND native_page_count + ocr_page_count = page_count, false) AND finished_at IS NOT NULL)".freeze

  def up
    remove_check_constraint :document_text_extractions, name: NAME
    add_check_constraint :document_text_extractions, NEW, name: NAME
  end

  def down
    remove_check_constraint :document_text_extractions, name: NAME
    add_check_constraint :document_text_extractions, OLD, name: NAME
  end
end
