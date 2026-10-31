// The API returns Rails' English validation messages (422 details); the
// common ones are shown in Portuguese, anything else as sent.
const MESSAGES: Record<string, string> = {
  "can't be blank": 'obrigatório',
  'has already been taken': 'já está em uso',
  'is invalid': 'inválido',
  'is not included in the list': 'valor inválido',
  'is not a number': 'deve ser um número',
  'not found': 'não encontrado nesta organização',
  'is archived': 'está arquivado',
  'must exist': 'obrigatório',
  'is not a valid CPF': 'CPF inválido',
  'is not a valid CNPJ': 'CNPJ inválido',
  'must include at least one lessor': 'inclua ao menos um locador',
  'must not repeat a counterparty': 'cada parte só pode aparecer uma vez',
  'can only change while the lease is a draft': 'só pode ser alterado enquanto o contrato for rascunho',
  'is empty': 'o arquivo está vazio',
  'is too large (maximum is 50 MB)': 'o arquivo passa de 50 MB',
  'must be a PDF, JPEG, PNG or TIFF file': 'envie um PDF, JPEG, PNG ou TIFF',
  'has already been uploaded': 'este arquivo já foi enviado nesta organização',
  'the lease already has an original contract': 'este contrato já tem um contrato original',
}

export function translateError(message: string): string {
  if (MESSAGES[message]) return MESSAGES[message]
  const tooLong = /^is too long \(maximum is (\d+) characters\)$/.exec(message)
  if (tooLong) return `máximo de ${tooLong[1]} caracteres`
  const uploadedAs = /^has already been uploaded as "(.*)" \(version (\d+)\)$/.exec(message)
  if (uploadedAs) return `este arquivo já foi enviado como "${uploadedAs[1]}" (versão ${uploadedAs[2]})`
  const greaterThan = /^must be greater than (\d+)$/.exec(message)
  if (greaterThan) return `deve ser maior que ${greaterThan[1]}`
  return message
}
