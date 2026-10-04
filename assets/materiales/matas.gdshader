shader_type spatial;
render_mode cull_disabled;

// Matas de la estepa: coirón, pasto de orilla, cojines de neneo y piedras sueltas.
// Lo arma scripts/multi_mesh_instance_3d.gd: cada tipo de mata es una grilla de copias de una malla.
// La grilla viaja con la cámara (cada copia salta al otro lado cuando queda lejos), pero el lugar,
// el tamaño y el color de cada mata salen de su casilla del mapa, así que una mata está siempre en
// el mismo sitio. La placa lee la altura del piso y qué suelo hay, y decide si ahí crece la mata.
// El viento sopla del oeste: las matas se inclinan hacia el este y las ráfagas pasan como olas.

uniform sampler2D u_alturas : filter_linear, repeat_disable;
uniform sampler2D u_suelos : filter_linear, repeat_disable;
uniform sampler2D u_pisado : filter_linear, repeat_disable;
uniform mat4 u_mundo_a_mapa;
uniform float u_escala_altura = 0.01;

uniform float paso = 2.0;
uniform float lado = 128.0;
uniform float semilla = 0.0;
uniform float densidad : hint_range(0.0, 1.0) = 0.7;
uniform float manchones : hint_range(0.0, 1.0) = 0.5;
// Cuánto le gusta cada suelo: estepa, tierra pisada, vega y canto rodado.
uniform vec4 gusto_suelo = vec4(1.0, 0.0, 0.3, 0.0);
// Altura del piso entre la que crece (metros); hacia los bordes se va raleando en "rampa_altura" metros.
uniform float altura_min = -1000.0;
uniform float altura_max = 10000.0;
uniform float rampa_altura = 40.0;
// 1: la mata se acuesta sobre la pendiente (piedras, cojines, manchones de nieve). 0: crece derecha.
uniform float acostar : hint_range(0.0, 1.0) = 0.0;
// Dónde está Zenón: las matas que pisa se apartan y se aplastan (apartar = 0 las deja quietas).
uniform vec3 u_zenon = vec3(0.0, -1000.0, 0.0);
uniform float apartar : hint_range(0.0, 1.0) = 1.0;
uniform float distancia_fin = 110.0;
uniform float esfumado = 28.0;
uniform vec2 tamano = vec2(0.8, 1.5);
uniform float alto_malla = 0.5;
uniform float hundir = 0.03;
// Cuánto pesa la forma de la malla en la luz (0: como el piso; más: se notan las caras).
uniform float relieve = 0.45;
uniform float viento : hint_range(0.0, 1.0) = 0.16;
uniform vec3 color_a : source_color = vec3(0.72, 0.62, 0.32);
uniform vec3 color_b : source_color = vec3(0.48, 0.52, 0.34);
uniform vec3 color_vega : source_color = vec3(0.42, 0.5, 0.26);

varying vec3 tinte;

vec4 azar4(vec2 p) {
	vec4 q = vec4(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)), dot(p, vec2(419.2, 371.9)), dot(p, vec2(98.7, 234.1)));
	return fract(sin(q) * 43758.5453);
}

float ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = azar4(i).x;
	float b = azar4(i + vec2(1.0, 0.0)).x;
	float c = azar4(i + vec2(0.0, 1.0)).x;
	float d = azar4(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	// la casilla de esta copia, llevada a la vuelta más cercana a la cámara
	vec3 base = MODEL_MATRIX[3].xyz;
	float periodo = paso * lado;
	vec2 camara = CAMERA_POSITION_WORLD.xz;
	vec2 casilla = base.xz + floor((camara - base.xz) / periodo + 0.5) * periodo;
	vec2 id = floor(casilla / paso + 0.5) + vec2(semilla * 17.0, semilla * 31.0);
	vec4 azar = azar4(id);
	vec2 pos = casilla + (azar.xy - 0.5) * paso * 0.9;

	// el piso en ese lugar: altura y suelos
	vec2 celda = (u_mundo_a_mapa * vec4(pos.x, 0.0, pos.y, 1.0)).xz;
	vec2 uv = (celda + 0.5) / vec2(textureSize(u_alturas, 0));
	float piso = texture(u_alturas, uv).r * u_escala_altura;
	vec4 suelo = texture(u_suelos, uv);
	suelo /= max(suelo.r + suelo.g + suelo.b + suelo.a, 0.001);

	// ¿crece acá? depende del suelo y de manchones grandes, para que no quede parejo
	float gusto = clamp(dot(suelo, gusto_suelo), 0.0, 1.0);
	float mancha = mix(1.0, smoothstep(0.25, 0.75, ruido(id * paso * 0.035)) * 1.6, manchones);
	float por_altura = smoothstep(altura_min, altura_min + rampa_altura, piso) * (1.0 - smoothstep(altura_max - rampa_altura, altura_max, piso));
	// comparación estricta: donde la cuenta da 0 (tierra pisada, agua, fuera de altura) no crece nunca
	float crece = (densidad * gusto * mancha * por_altura > azar.z + 0.002) ? 1.0 : 0.0;
	crece *= step(texture(u_pisado, uv).r, 0.25);
	float d = distance(camara, pos);
	crece *= 1.0 - smoothstep(distancia_fin - esfumado, distancia_fin, d);
	float escala = mix(tamano.x, tamano.y, azar.w) * crece;

	// girada, a su tamaño y con el viento
	float giro = azar.x * 6.2831853;
	float c = cos(giro);
	float s = sin(giro);
	vec3 v = vec3(VERTEX.x * c - VERTEX.z * s, VERTEX.y * mix(0.8, 1.25, azar.y), VERTEX.x * s + VERTEX.z * c) * escala;
	vec3 n = vec3(NORMAL.x * c - NORMAL.z * s, NORMAL.y, NORMAL.x * s + NORMAL.z * c);
	float peso = clamp(VERTEX.y / alto_malla, 0.0, 1.0);
	peso *= peso;
	float rafaga = sin(TIME * 1.3 - pos.x * 0.11 + pos.y * 0.05) * 0.5 + 0.5;
	float temblor = sin(TIME * 4.3 + pos.x * 1.7 + azar.x * 6.28) * 0.25;
	float empuje = viento * peso * escala * (0.35 + 0.65 * rafaga + temblor * rafaga);
	vec2 hacia = pos - u_zenon.xz;
	float pisada = (1.0 - smoothstep(0.3, 1.2, length(hacia))) * apartar * peso;
	v.xz += normalize(hacia + vec2(0.0001)) * pisada * 0.4 * escala;
	v.y *= 1.0 - 0.5 * pisada;
	v.x += empuje;
	v.z += empuje * 0.25 * sin(TIME * 2.1 + azar.y * 6.28);
	v.y -= empuje * empuje * 0.6;

	if (acostar > 0.0) {
		// cuánto sube el piso por metro hacia el este y hacia el sur
		vec2 un_metro = vec2(u_mundo_a_mapa[0][0], u_mundo_a_mapa[2][2]) / vec2(textureSize(u_alturas, 0));
		float sube_x = (texture(u_alturas, uv + vec2(un_metro.x * 2.0, 0.0)).r * u_escala_altura - piso) * 0.5;
		float sube_z = (texture(u_alturas, uv + vec2(0.0, un_metro.y * 2.0)).r * u_escala_altura - piso) * 0.5;
		v.y += (v.x * sube_x + v.z * sube_z) * acostar;
	}

	VERTEX = vec3(pos.x, piso - hundir * escala, pos.y) + v - base;
	// la luz la lee casi como el piso: así la mata no queda negra del lado de la sombra
	NORMAL = normalize(vec3(0.0, 1.0, 0.0) + n * relieve);
	tinte = mix(mix(color_a, color_b, azar.w), color_vega, clamp(suelo.b * 1.4, 0.0, 1.0) * 0.8) * mix(0.82, 1.1, azar.y);
}

void fragment() {
	// las hojas son finas: las dos caras reciben la misma luz
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// En el borde de una hoja fina el color puede salirse de rango (y dar un destello): se acota.
	ALBEDO = pow(clamp(COLOR.rgb, vec3(0.0), vec3(1.5)), vec3(2.2)) * tinte;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
