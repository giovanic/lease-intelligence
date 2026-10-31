interface SelectFilterProps<T extends string> {
  label: string
  value: string
  options: readonly T[]
  labels: Record<T, string>
  onChange: (value: string) => void
}

/** A list filter with an "all" option (empty value). */
export function SelectFilter<T extends string>({ label, value, options, labels, onChange }: SelectFilterProps<T>) {
  return (
    <label className="filter">
      <span className="filter__label">{label}</span>
      <select value={value} onChange={(event) => onChange(event.target.value)}>
        <option value="">Todos</option>
        {options.map((option) => (
          <option key={option} value={option}>
            {labels[option]}
          </option>
        ))}
      </select>
    </label>
  )
}
