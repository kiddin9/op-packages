/**
 * A disabled save button is not necessarily saving: unchanged forms are also disabled.
 * Only a running operation may use the waiting cursor.
 */
export function saveButtonCursor(busy: boolean): 'disabled:cursor-wait' | 'disabled:cursor-not-allowed' {
  return busy ? 'disabled:cursor-wait' : 'disabled:cursor-not-allowed';
}
