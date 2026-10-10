import { useEffect, useState } from 'preact/hooks';
import { fetchGuestWifiQr, fetchWifiQr } from '../api/smartsafehub';
import { DownloadIcon } from './Icons';
import { createQrMatrix } from '../utils/qrMatrix';

export function wifiQrPayload(ssid: string, security: string, password: string): string {
  const escape = (value: string) => value.replace(/([\\;,:"])/g, '\\$1');
  const type = security === 'none' ? 'nopass' : security === 'sae' ? 'WPA3' : 'WPA';
  return `WIFI:T:${type};S:${escape(ssid)};P:${escape(password)};;`;
}

// Keep the quiet zone in the downloaded image identical to the on-screen SVG.
export function wifiQrFilename(ssid: string): string {
  const safeName = ssid.replace(/[\\/:*?"<>|\x00-\x1f\x7f]/g, '_').replace(/[. ]+$/g, '').trim();
  return `${(safeName || 'Wi-Fi').slice(0, 64)}-QR.png`;
}

export function drawWifiQrPng(
  matrix: boolean[][],
  context: CanvasRenderingContext2D,
  moduleSize = 8,
): void {
  const margin = 4;
  const count = matrix.length;
  const size = (count + margin * 2) * moduleSize;
  context.fillStyle = '#ffffff';
  context.fillRect(0, 0, size, size);
  context.fillStyle = '#000000';
  matrix.forEach((row, y) => row.forEach((dark, x) => {
    if (dark) context.fillRect((x + margin) * moduleSize, (y + margin) * moduleSize, moduleSize, moduleSize);
  }));
}

export function WifiQrDialog({ section, guest = false, onClose }: { section: string; guest?: boolean; onClose: () => void }) {
  const [qr, setQr] = useState<{ ssid: string; matrix: boolean[][] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [downloadError, setDownloadError] = useState<string | null>(null);
  useEffect(() => {
    let active = true;
    void (guest ? fetchGuestWifiQr() : fetchWifiQr(section)).then((data) => {
      if (!active) return;
      try { setQr({ ssid: data.ssid, matrix: createQrMatrix(wifiQrPayload(data.ssid, data.security, data.password)) }); }
      catch { setError('QR 코드를 생성할 수 없습니다.'); }
    }).catch(() => { if (active) setError('Wi-Fi 정보를 불러오지 못했습니다.'); });
    return () => { active = false; setQr(null); };
  }, [section, guest]);
  const count = qr?.matrix.length ?? 0;
  const downloadQr = () => {
    if (!qr) return;
    setDownloadError(null);
    try {
      const moduleSize = 8;
      const size = (qr.matrix.length + 8) * moduleSize;
      const canvas = document.createElement('canvas');
      canvas.width = size;
      canvas.height = size;
      const context = canvas.getContext('2d');
      if (!context) throw new Error('Canvas is not supported');
      drawWifiQrPng(qr.matrix, context, moduleSize);
      const link = document.createElement('a');
      link.href = canvas.toDataURL('image/png');
      link.download = wifiQrFilename(qr.ssid);
      link.click();
    } catch {
      setDownloadError('QR 코드 이미지를 저장하지 못했습니다. 다시 시도해 주세요.');
    }
  };
  return (
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4" role="presentation" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <section role="dialog" aria-modal="true" aria-label="Wi-Fi QR 코드" class="w-full max-w-sm rounded-2xl bg-white p-5 text-center text-slate-950 shadow-2xl sm:p-7">
        <h2 class="m-0 text-xl font-extrabold">Wi-Fi QR 코드</h2>
        <p class="mt-2 break-all text-sm font-semibold text-slate-600">{qr?.ssid ?? 'Wi-Fi 정보를 확인하는 중'}</p>
        {error ? <p role="alert" class="my-6 text-sm font-bold text-red-700">{error}</p> : null}
        {!qr && !error ? <p class="my-6 text-sm">QR 코드를 만드는 중...</p> : null}
        {qr ? <div class="mx-auto my-5 w-full max-w-[288px] rounded-xl border border-slate-200 bg-white p-3">
          <svg class="block h-auto w-full" viewBox={`0 0 ${count + 8} ${count + 8}`} role="img" aria-label={`${qr.ssid} Wi-Fi 연결 QR 코드`} shape-rendering="crispEdges">
            <rect width={count + 8} height={count + 8} fill="white" />
            {qr.matrix.map((row, y) => row.map((dark, x) => dark ? <rect key={`${y}-${x}`} x={x + 4} y={y + 4} width="1" height="1" fill="black" /> : null))}
          </svg>
        </div> : null}
        <p class="text-xs leading-5 text-slate-500">
          <span class="block">카메라로 스캔해 Wi-Fi에 연결하세요.</span>
          <span class="block">QR 코드에는 비밀번호가 포함됩니다.</span>
        </p>
        {downloadError ? <p role="alert" class="mt-3 text-sm font-bold text-red-700">{downloadError}</p> : null}
        {qr ? (
          <button
            class="mt-5 inline-flex min-h-11 w-full items-center justify-center gap-2 rounded-xl bg-teal-700 px-4 font-extrabold text-white transition hover:bg-teal-800 focus:outline-none focus-visible:ring-4 focus-visible:ring-teal-200"
            onClick={downloadQr}
            type="button"
          >
            <DownloadIcon class="size-5" />
            QR 코드 다운로드
          </button>
        ) : null}
        <button class="mt-2 min-h-11 w-full rounded-xl border border-slate-300 bg-white px-4 font-extrabold text-slate-700 transition hover:bg-slate-50" onClick={onClose} type="button">닫기</button>
      </section>
    </div>
  );
}
