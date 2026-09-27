import { RpcError } from '../api/rpc';

export function errorMessage(error: unknown, fallback: string): string {
  return error instanceof RpcError || error instanceof Error
    ? error.message
    : fallback;
}
