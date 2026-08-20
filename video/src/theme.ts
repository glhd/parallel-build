/**
 * One palette for the whole video. The chain colours are the ones
 * `parallel.sh` actually hands out: bold cyan to the first chain declared,
 * bold magenta to the second.
 */
export const theme = {
	page: '#07090d',
	pageGlow: '#0f1622',
	panel: '#0e131b',
	panelEdge: 'rgba(255,255,255,0.07)',

	term: {
		bg: '#0b0f16',
		chrome: '#151b26',
		fg: '#c9d1d9',
		dim: '#5c6672',
	},

	composer: '#56c8e0',
	npm: '#c887ec',

	red: '#e5545f',
	green: '#7ec96b',
	yellow: '#e2b84f',

	text: '#e8edf5',
	textDim: '#8b95a5',
	textFaint: '#5a6472',
} as const;

export const mono = '"JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, monospace';
export const sans = 'Inter, system-ui, -apple-system, "Segoe UI", sans-serif';
