# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # CPF/CNPJ and phone of counterparties: personal data under LGPD.
  :tax_id, :phone,
  # Uploaded contract files: the logged UploadedFile shows the original
  # filename, which often carries a person's or company's name.
  :file,
  # Extracted contract text (document_text_pages.text, docs/adr/0016): masked
  # in SQL bind logs and in #inspect. Exact name — a partial :text would
  # also hide unrelated keys like "context".
  /\Atext\z/,
  # AI-extracted candidates (extracted_fields.value_text: party names, clause
  # summaries — docs/adr/0017); value_tax_id is already covered by :tax_id.
  /\Avalue_text\z/,
  # Review decisions (docs/adr/0019): a corrected value (e.g. a party's name
  # and CPF) and the reviewer's reason are contract content / personal data.
  /\Avalue\z/, :reason
]
