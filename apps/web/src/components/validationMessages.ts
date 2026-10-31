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
}

export function translateError(message: string): string {
  if (MESSAGES[message]) return MESSAGES[message]
  const tooLong = /^is too long \(maximum is (\d+) characters\)$/.exec(message)
  if (tooLong) return `máximo de ${tooLong[1]} caracteres`
  const greaterThan = /^must be greater than (\d+)$/.exec(message)
  if (greaterThan) return `deve ser maior que ${greaterThan[1]}`
  return message
}
