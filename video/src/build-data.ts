/**
 * The build this video draws.
 *
 * The output is real: a Laravel React starter kit installed and built in a
 * container, with `composer install`, `npm ci` and `npm run build` each run on
 * its own and its output kept. Lines were thinned to what fits a terminal this
 * size, and composer's `Cloning ... from cache` was put back to the
 * `Extracting archive` that `--prefer-dist` prints when it can reach the CDN.
 *
 * The durations are the shape of a cold build on a real machine, not the ones
 * this container gave, where the npm registry is a few milliseconds away and
 * nothing is representative: a full `composer install` is the long pole, and
 * npm gets through its install and its bundle while composer is still going.
 * `at` is where in its own step a line was printed, from 0 to 1.
 */
export const BUILD = {
	steps: {
		composer: {
			seconds: 60,
			lines: [
			{at: 0.005, text: "Installing dependencies from lock file"},
			{at: 0.02, text: "Verifying lock file contents can be installed on current platform."},
			{at: 0.04, text: "Package operations: 99 installs, 0 updates, 0 removals"},
			{at: 0.08, text: "  - Downloading dasprid/enum (1.0.7)"},
			{at: 0.1127, text: "  - Downloading symfony/polyfill-php80 (v1.37.0)"},
			{at: 0.1455, text: "  - Downloading symfony/polyfill-intl-grapheme (v1.41.0)"},
			{at: 0.1782, text: "  - Downloading graham-campbell/result-type (v1.1.4)"},
			{at: 0.2109, text: "  - Downloading symfony/polyfill-php86 (v1.41.0)"},
			{at: 0.2436, text: "  - Downloading symfony/mailer (v8.1.2)"},
			{at: 0.2764, text: "  - Downloading symfony/translation-contracts (v3.7.1)"},
			{at: 0.3091, text: "  - Downloading league/mime-type-detection (1.17.0)"},
			{at: 0.3418, text: "  - Downloading laravel/prompts (v0.3.23)"},
			{at: 0.3745, text: "  - Downloading symfony/serializer (v8.1.4)"},
			{at: 0.4073, text: "  - Downloading phpdocumentor/type-resolver (2.0.0)"},
			{at: 0.47, text: "  - Installing dasprid/enum (1.0.7): Extracting archive"},
			{at: 0.5023, text: "  - Installing fruitcake/php-cors (v1.4.0): Extracting archive"},
			{at: 0.5346, text: "  - Installing guzzlehttp/guzzle (8.0.2): Extracting archive"},
			{at: 0.5669, text: "  - Installing symfony/service-contracts (v3.7.1): Extracting archive"},
			{at: 0.5992, text: "  - Installing tijsverkoyen/css-to-inline-styles (v2.4.0): Extracting archive"},
			{at: 0.6315, text: "  - Installing symfony/polyfill-intl-idn (v1.38.1): Extracting archive"},
			{at: 0.6638, text: "  - Installing symfony/mailer (v8.1.2): Extracting archive"},
			{at: 0.6962, text: "  - Installing nunomaduro/termwind (v2.4.0): Extracting archive"},
			{at: 0.7285, text: "  - Installing monolog/monolog (3.10.0): Extracting archive"},
			{at: 0.7608, text: "  - Installing dflydev/dot-access-data (v3.0.3): Extracting archive"},
			{at: 0.7931, text: "  - Installing laravel/chisel (v0.1.1): Extracting archive"},
			{at: 0.8254, text: "  - Installing symfony/property-info (v8.1.4): Extracting archive"},
			{at: 0.8577, text: "  - Installing phpdocumentor/reflection-docblock (6.0.3): Extracting archive"},
			{at: 0.925, text: "Generating optimized autoload files"},
			{at: 0.955, text: "> @php artisan package:discover --ansi"},
			{at: 0.985, text: "  INFO  Discovering packages."},
			],
		},
		npmCi: {
			seconds: 35,
			lines: [
			{at: 0.965, text: "added 465 packages in 34s"},
			{at: 0.985, text: "179 packages are looking for funding"},
			{at: 0.998, text: "  run `npm fund` for details"},
			],
		},
		npmBuild: {
			seconds: 20,
			lines: [
			{at: 0.02, text: "> build"},
			{at: 0.05, text: "> vite build"},
			{at: 0.12, text: "vite v8.2.2 building client environment for production..."},
			{at: 0.2, text: "[plugin @laravel/vite-plugin-wayfinder] Types generated for actions"},
			{at: 0.28, text: "transforming..."},
			{at: 0.55, text: "\u2713 2311 modules transformed."},
			{at: 0.62, text: "rendering chunks..."},
			{at: 0.68, text: "computing gzip size..."},
			{at: 0.74, text: "public/build/assets/button-ytm1aaLp.js                 5.24 kB \u2502 gzip:  2.32 kB"},
			{at: 0.76, text: "public/build/assets/profile-Iifm03Hf.js                6.91 kB \u2502 gzip:  2.35 kB"},
			{at: 0.78, text: "public/build/assets/dist-lkX9BXJj.js                   7.02 kB \u2502 gzip:  2.72 kB"},
			{at: 0.8, text: "public/build/assets/login-AK2mYXY8.js                  7.76 kB \u2502 gzip:  3.17 kB"},
			{at: 0.82, text: "public/build/assets/react-CoZ4deAL.js                 13.90 kB \u2502 gzip:  4.62 kB"},
			{at: 0.84, text: "public/build/assets/use-two-factor-auth-BfMcP4kg.js   17.09 kB \u2502 gzip:  6.19 kB"},
			{at: 0.86, text: "public/build/assets/createLucideIcon-DDt7yPs0.js      28.28 kB \u2502 gzip:  9.20 kB"},
			{at: 0.88, text: "public/build/assets/welcome-rXPQBXwl.js               30.64 kB \u2502 gzip:  6.45 kB"},
			{at: 0.9, text: "public/build/assets/security-BeZq55QQ.js              31.58 kB \u2502 gzip:  9.96 kB"},
			{at: 0.92, text: "public/build/assets/app-B1SonfBt.js                  174.84 kB \u2502 gzip: 53.57 kB"},
			{at: 0.94, text: "public/build/assets/wayfinder-BN-kYZsK.js            316.85 kB \u2502 gzip: 99.69 kB"},
			{at: 0.995, text: "\u2713 built in 19.4s"},
			],
		},
	},
	/** What the two chains come to: the longer of them, composer's 60s. */
	parallelSeconds: 60,
} as const;
