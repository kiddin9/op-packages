import {
  BarController,
  BarElement,
  CategoryScale,
  Chart as ChartJS,
  LinearScale,
  Tooltip,
  type ChartOptions,
} from 'chart.js';
import { useEffect, useRef } from 'preact/hooks';

import { formatNumber } from '../app/format';
import type { SafeShieldStatisticsBucket } from '../types/safeshield';

ChartJS.register(
  BarController,
  BarElement,
  CategoryScale,
  LinearScale,
  Tooltip,
);

interface SafeShieldBlockedBarChartProps {
  buckets: SafeShieldStatisticsBucket[];
}

const HOUR_FORMATTER = new Intl.DateTimeFormat('ko-KR', {
  hour: '2-digit',
  hour12: false,
});
const AXIS_COLOR = '#94a3b8';
const GRID_COLOR = 'rgba(148, 163, 184, 0.18)';
const BAR_COLOR = '#0d9488';
const BAR_HOVER_COLOR = '#0f766e';

function formatHour(bucketStart: number): string {
  return HOUR_FORMATTER.format(new Date(bucketStart * 1_000));
}

function displayLabels(buckets: SafeShieldStatisticsBucket[]): string[] {
  return buckets.map((bucket, index) =>
    index % 3 === 0 || index === buckets.length - 1
      ? formatHour(bucket.bucketStart)
      : '',
  );
}

export function SafeShieldBlockedBarChart({
  buckets,
}: SafeShieldBlockedBarChartProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const chartRef = useRef<ChartJS<'bar', number[], string> | null>(null);
  const bucketsRef = useRef(buckets);

  bucketsRef.current = buckets;

  useEffect(() => {
    const canvas = canvasRef.current;

    if (!canvas) {
      return;
    }

    const reduceMotion = window.matchMedia(
      '(prefers-reduced-motion: reduce)',
    ).matches;
    const fontFamily = window.getComputedStyle(canvas).fontFamily;
    const options: ChartOptions<'bar'> = {
      animation: reduceMotion
        ? false
        : {
            duration: 500,
            easing: 'easeOutQuart',
          },
      maintainAspectRatio: false,
      responsive: true,
      interaction: {
        intersect: false,
        mode: 'index',
      },
      plugins: {
        legend: {
          display: false,
        },
        tooltip: {
          displayColors: false,
          callbacks: {
            title: (items) => {
              const index = items[0]?.dataIndex ?? -1;
              const bucket = bucketsRef.current[index];

              return bucket ? formatHour(bucket.bucketStart) : '';
            },
            label: (context) =>
              `차단 ${formatNumber(Number(context.raw ?? 0))}`,
            afterLabel: (context) => {
              const bucket = bucketsRef.current[context.dataIndex];

              return bucket
                ? `DNS 요청 ${formatNumber(bucket.queries)}`
                : '';
            },
          },
        },
      },
      scales: {
        x: {
          border: {
            display: false,
          },
          grid: {
            display: false,
          },
          ticks: {
            autoSkip: false,
            color: AXIS_COLOR,
            font: {
              family: fontFamily,
              size: 11,
              weight: 700,
            },
            maxRotation: 0,
            minRotation: 0,
          },
        },
        y: {
          beginAtZero: true,
          border: {
            display: false,
          },
          grid: {
            color: GRID_COLOR,
          },
          ticks: {
            color: AXIS_COLOR,
            font: {
              family: fontFamily,
              size: 11,
              weight: 700,
            },
            maxTicksLimit: 4,
            precision: 0,
          },
        },
      },
    };

    chartRef.current = new ChartJS(canvas, {
      type: 'bar',
      data: {
        labels: displayLabels(bucketsRef.current),
        datasets: [
          {
            data: bucketsRef.current.map((bucket) => bucket.blocked),
            backgroundColor: BAR_COLOR,
            hoverBackgroundColor: BAR_HOVER_COLOR,
            borderRadius: 4,
            borderSkipped: false,
            barPercentage: 0.82,
            categoryPercentage: 0.9,
            maxBarThickness: 24,
          },
        ],
      },
      options,
    });

    return () => {
      chartRef.current?.destroy();
      chartRef.current = null;
    };
  }, []);

  useEffect(() => {
    const chart = chartRef.current;

    if (!chart) {
      return;
    }

    chart.data.labels = displayLabels(buckets);
    chart.data.datasets[0]!.data = buckets.map((bucket) => bucket.blocked);
    chart.update();
  }, [buckets]);

  return (
    <div class="mt-5 h-44 sm:h-52">
      <canvas
        aria-label="최근 24시간 시간대별 SafeShield 차단 요청"
        ref={canvasRef}
        role="img"
      >
        최근 24시간 시간대별 SafeShield 차단 요청 차트
      </canvas>
    </div>
  );
}
