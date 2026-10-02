extends SceneTree
## Bakes the wind-sea slope tile of resources/shaders/garda_water.gdshader into textures/water/garda_waves.res.
## godot --headless --path . --script res://tools/water/build_wave_texture.gd
## A random sea from an equilibrium-range spectrum (equal slope variance per octave, short crests spread
## around the wind along +x), inverse-FFT to slopes. RG: slope x, y; BA: their squares, so the mipmaps
## average slope and squared slope and their difference is the variance a pixel loses (LEAN mapping).
## Slopes are scaled to a mean squared slope of 1: the shader sets the real one from the wind.
const OUT := "res://textures/water/garda_waves.res"
const N := 512
const PEAK := 8.0 # peak wavelength: an eighth of the tile (6 m on the shader's 48 m tile)
const CUTOFF := 0.45 # of the Nyquist frequency: the shortest waves keep a few texels
const SEED := 20261002

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_bake()
	quit()

func _bake() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	# Random spectrum, then Hermitian symmetry: the slope fields come out real.
	var gr := PackedFloat64Array()
	var gi := PackedFloat64Array()
	gr.resize(N * N)
	gi.resize(N * N)
	for i in N * N:
		gr[i] = rng.randfn()
		gi[i] = rng.randfn()
	var re := PackedFloat64Array()
	var im := PackedFloat64Array()
	re.resize(N * N)
	im.resize(N * N)
	var k_peak := TAU * PEAK
	var k_max := PI * N * CUTOFF
	for y in N:
		for x in N:
			var kx := TAU * float(x if x < N / 2 else x - N)
			var ky := TAU * float(y if y < N / 2 else y - N)
			var k := sqrt(kx * kx + ky * ky)
			if k == 0.0 or k > k_max:
				continue
			# Height spectrum k^-4: equal slope variance per octave above the peak, cut below it.
			var spectrum := exp(-1.25 * pow(k_peak / k, 2.0)) / pow(k, 4.0)
			spectrum *= 1.0 - smoothstep(k_max * 0.7, k_max, k)
			var c := kx / k
			spectrum *= 0.15 + c * c # short crests: wide spreading around the wind axis
			var a := sqrt(spectrum * 0.5)
			var i := y * N + x
			var j := ((N - y) % N) * N + (N - x) % N
			var hr := 0.5 * (gr[i] + gr[j]) * a
			var hi := 0.5 * (gi[i] - gi[j]) * a
			# slope x + i slope y = ifft(i kx H - ky H): both real, packed in one transform.
			re[i] = -kx * hi - ky * hr
			im[i] = kx * hr - ky * hi
	_fft_2d(re, im)
	var total := 0.0
	for i in N * N:
		total += re[i] * re[i] + im[i] * im[i]
	var scale := 1.0 / sqrt(total / float(N * N))
	var data := PackedFloat32Array()
	data.resize(N * N * 4)
	for i in N * N:
		var sx := re[i] * scale
		var sy := im[i] * scale
		data[i * 4] = sx
		data[i * 4 + 1] = sy
		data[i * 4 + 2] = sx * sx
		data[i * 4 + 3] = sy * sy
	var image := Image.create_from_data(N, N, false, Image.FORMAT_RGBAF, data.to_byte_array())
	image.generate_mipmaps() # box filter: exact means of slope and squared slope
	image.convert(Image.FORMAT_RGBAH)
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var error := ResourceSaver.save(ImageTexture.create_from_image(image), OUT, ResourceSaver.FLAG_COMPRESS)
	assert(error == OK, "Cannot save " + OUT)
	print("PASS: WAVE TEXTURE BUILT %s" % OUT)

# In-place inverse transform (unnormalized: the slopes are rescaled anyway), rows then columns.
func _fft_2d(re: PackedFloat64Array, im: PackedFloat64Array) -> void:
	var row_re := PackedFloat64Array()
	var row_im := PackedFloat64Array()
	row_re.resize(N)
	row_im.resize(N)
	for pass_ in 2:
		for line in N:
			for t in N:
				var i := line * N + t if pass_ == 0 else t * N + line
				row_re[t] = re[i]
				row_im[t] = im[i]
			_fft(row_re, row_im)
			for t in N:
				var i := line * N + t if pass_ == 0 else t * N + line
				re[i] = row_re[t]
				im[i] = row_im[t]

func _fft(re: PackedFloat64Array, im: PackedFloat64Array) -> void:
	var j := 0
	for i in range(1, N):
		var bit := N >> 1
		while j & bit:
			j ^= bit
			bit >>= 1
		j |= bit
		if i < j:
			var t := re[i]; re[i] = re[j]; re[j] = t
			t = im[i]; im[i] = im[j]; im[j] = t
	var size := 2
	while size <= N:
		var step := TAU / float(size) # positive exponent: inverse
		for start in range(0, N, size):
			for k in size / 2:
				var wr := cos(step * k)
				var wi := sin(step * k)
				var a := start + k
				var b := a + size / 2
				var tr := re[b] * wr - im[b] * wi
				var ti := re[b] * wi + im[b] * wr
				re[b] = re[a] - tr
				im[b] = im[a] - ti
				re[a] += tr
				im[a] += ti
		size <<= 1
