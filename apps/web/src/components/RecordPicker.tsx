import { useEffect, useId, useState } from 'react'
import { useApiQuery } from '../hooks/useApiQuery'

export interface PickerOption {
  id: string
  label: string
}

interface RecordPickerProps {
  /** The selected record, kept as an option even when outside the results. */
  value: PickerOption | null
  onChange: (option: PickerOption | null) => void
  /** Fetches up to a few dozen matches for the typed text. */
  search: (text: string) => Promise<PickerOption[]>
  /** Identifies the search for useApiQuery (tenant + resource). */
  searchKey: string
  placeholder: string
  disabled?: boolean
  invalid?: boolean
  label: string
}

const DEBOUNCE_MS = 300

/**
 * A search box plus a select of matches, for picking one record of a
 * collection that may be too large to list whole (the API caps pages at 100).
 */
export function RecordPicker({ value, onChange, search, searchKey, placeholder, disabled, invalid, label }: RecordPickerProps) {
  const selectId = useId()
  const [text, setText] = useState('')
  const [applied, setApplied] = useState('')

  useEffect(() => {
    const timer = window.setTimeout(() => setApplied(text.trim()), DEBOUNCE_MS)
    return () => window.clearTimeout(timer)
  }, [text])

  const { state, retry } = useApiQuery(`${searchKey}:${applied}`, () => search(applied))
  const results = state.status === 'success' ? state.data : []
  const options = value && !results.some((option) => option.id === value.id) ? [value, ...results] : results

  return (
    <div className={invalid ? 'picker picker--invalid' : 'picker'}>
      <input
        type="search"
        aria-label={`Buscar ${label}`}
        placeholder={placeholder}
        value={text}
        disabled={disabled}
        onChange={(event) => setText(event.target.value)}
        onKeyDown={(event) => {
          // Enter searches immediately instead of submitting the whole form.
          if (event.key === 'Enter') {
            event.preventDefault()
            setApplied(text.trim())
          }
        }}
      />
      <select
        id={selectId}
        aria-label={label}
        value={value?.id ?? ''}
        disabled={disabled}
        onChange={(event) => onChange(options.find((option) => option.id === event.target.value) ?? null)}
      >
        <option value="">
          {state.status === 'loading' ? 'Buscando…' : options.length === 0 ? 'Nenhum resultado' : 'Selecione…'}
        </option>
        {options.map((option) => (
          <option key={option.id} value={option.id}>
            {option.label}
          </option>
        ))}
      </select>
      {state.status === 'error' && (
        <span className="field__error">
          Falha na busca: {state.message}{' '}
          <button type="button" className="button button--link" onClick={retry}>
            Tentar novamente
          </button>
        </span>
      )}
    </div>
  )
}
