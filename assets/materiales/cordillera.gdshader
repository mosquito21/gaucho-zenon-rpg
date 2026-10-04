shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;

// Montañas lejanas (la cordillera nevada y los cerros de bosque). Están a más de 2,5 km,
// donde la niebla del ambiente las borraría; por eso no usan esa niebla y se arreglan solas.
// Tampoco usan las luces de la escena: la luz se la pasa scripts/CicloDiaNoche.gd a cada momento,
// para poder elegir desde dónde les da (tanda 6):
// - de día, un sol 'de relieve': el de verdad, pero más bajo y corrido hacia el norte, así las
//   laderas no quedan parejas al mediodía; la sombra es fría (toma el color del cielo) y la luz, cálida;
// - quebradas y filos dibujados acá, que oscurecen el fondo y ladean la luz;
// - al atardecer, con el sol atrás, un filo de luz en las crestas;
// - de noche, la luna según su fase: con luna llena la nieve se lee clara y azulada y la roca se
//   despega apenas; con luna nueva queda la silueta. La roca nunca llega al brillo del cielo.
// El cuerpo se aclara con la distancia (los cerros de adelante quedan más oscuros y nítidos que la
// cordillera de atrás) y el pie se funde con el color del horizonte de cada hora.
uniform vec3 color_bruma : source_color = vec3(0.76, 0.8, 0.78);
uniform float brillo_pie = 1.0;
uniform float bruma_cerca : hint_range(0.0, 1.0) = 0.1;
uniform float bruma_lejos : hint_range(0.0, 1.0) = 0.42;
uniform float distancia_cerca = 2600.0;
uniform float distancia_lejos = 3900.0;
uniform float alto_horizonte = -15.0;
uniform float alto_claro = 90.0;

group_uniforms ajustes;
// Cuánto marcan las quebradas y los filos dibujados (0 las apaga).
uniform float relieve : hint_range(0.0, 2.0) = 1.0;
// Ancho de las quebradas, en metros.
uniform float ancho_quebradas = 110.0;
// El filo de luz en las crestas cuando el sol queda atrás.
uniform float contraluz : hint_range(0.0, 2.0) = 0.7;
// Cuánto alumbra la luna llena la nieve, y cuánto despega la roca del cielo (siempre por debajo de 1).
uniform float luna_nieve : hint_range(0.0, 3.0) = 1.0;
uniform float luna_roca : hint_range(0.0, 0.9) = 0.75;

group_uniforms luz_de_la_hora;
// Todo esto lo pisa CicloDiaNoche.gd en cada cuadro.
uniform vec3 color_sol : source_color = vec3(1.0, 0.95, 0.86);
uniform float fuerza_sol = 1.6;
uniform vec3 direccion_relieve = vec3(0.0, 0.59, -0.81);
uniform vec3 direccion_sol = vec3(0.0, 1.0, 0.0);
uniform vec3 color_sombra : source_color = vec3(0.40, 0.57, 0.71);
uniform float fuerza_sombra = 0.6;
uniform vec3 color_luna : source_color = vec3(0.62, 0.72, 1.0);
uniform float fuerza_luna = 0.0;
uniform vec3 direccion_luna = vec3(0.0, 1.0, 0.0);
uniform vec3 cielo_noche : source_color = vec3(0.05, 0.075, 0.14);

varying float bruma;
varying float pie;
varying vec3 lugar;
varying vec3 normal_mundo;

void vertex() {
	float lejos = smoothstep(distancia_cerca, distancia_lejos, length(VERTEX.xz));
	bruma = mix(bruma_cerca, bruma_lejos, lejos);
	pie = 1.0 - smoothstep(alto_horizonte, alto_claro, VERTEX.y);
	// La malla cuelga de un nodo que sigue a la cámara sin girar: sus coordenadas ya son las del mundo.
	lugar = VERTEX;
	normal_mundo = NORMAL;
}

float azar(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(azar(i), azar(i + vec2(1.0, 0.0)), f.x), mix(azar(i + vec2(0.0, 1.0)), azar(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Quebradas: franjas que bajan por la ladera torciéndose, con una segunda tanda más fina.
// Da 0 en el fondo de la quebrada y 1 en el filo.
float quebradas(float arco, float alto) {
	float tuerce = (ruido(vec2(arco / 310.0, alto / 130.0)) - 0.5) * 1.5;
	float gruesa = ruido(vec2(arco / ancho_quebradas + tuerce, alto / 260.0));
	float fina = ruido(vec2(arco / (ancho_quebradas * 0.45) + tuerce * 1.7 + 31.0, alto / 120.0));
	float q = 1.0 - abs(2.0 * gruesa - 1.0);
	return clamp(q * 0.7 + fina * 0.3, 0.0, 1.0);
}

void fragment() {
	vec3 n = normalize(normal_mundo);
	vec3 mira = normalize(-lugar);  // hacia la cámara
	if (dot(n, mira) < 0.0) {
		n = -n;
	}
	// Los colores de la malla están en sRGB: se pasan a lineal (acotados: con MSAA pueden salirse de 0..1).
	vec3 base = pow(clamp(COLOR.rgb, vec3(0.0), vec3(1.5)), vec3(2.2));
	float nieve = smoothstep(0.42, 0.72, dot(clamp(COLOR.rgb, vec3(0.0), vec3(1.0)), vec3(0.299, 0.587, 0.114)));

	// Quebradas y filos: oscurecen el fondo y ladean la normal hacia los costados.
	// El arco se mide a un radio fijo: con el radio de cada punto las franjas se acuestan y parecen estratos.
	float arco = atan(lugar.z, lugar.x) * 3200.0;
	float q = quebradas(arco, lugar.y);
	float dq = quebradas(arco + 14.0, lugar.y) - quebradas(arco - 14.0, lugar.y);
	vec3 costado = normalize(vec3(-lugar.z, 0.0, lugar.x));
	float marca = relieve * (1.0 - bruma * 0.6);
	n = normalize(n - costado * dq * 1.3 * marca);
	base *= mix(1.0, 0.72 + 0.42 * q, marca * (1.0 - nieve * 0.65));

	// De día: luz cálida según la ladera, sombra fría pareja.
	float ladera = clamp(dot(n, normalize(direccion_relieve)), 0.0, 1.0);
	vec3 color = base * (color_sol * fuerza_sol * ladera + color_sombra * fuerza_sombra);

	// Contraluz: con el sol detrás, las crestas (lo que mira hacia arriba) toman un filo de su color.
	float cresta = pow(1.0 - clamp(dot(n, mira), 0.0, 1.0), 2.0);
	float sol_atras_ancho = clamp(dot(normalize(direccion_sol), -mira), 0.0, 1.0);
	float sol_atras = pow(sol_atras_ancho, 6.0);
	color += color_sol * fuerza_sol * cresta * sol_atras * contraluz * 0.22;

	// De noche: la luna según su fase. La nieve la devuelve; la roca apenas se despega del cielo.
	float luna = clamp(fuerza_luna * 2.0, 0.0, 1.0);
	float ladera_luna = clamp(dot(n, normalize(direccion_luna)) * 0.6 + 0.4, 0.0, 1.0);
	color += base * color_luna * fuerza_luna * ladera_luna * luna_nieve * nieve * 1.6;
	color += cielo_noche * luna_roca * luna * (0.55 + 0.45 * ladera_luna) * (1.0 - nieve);

	// La distancia la aclara hacia el color del horizonte; el pie se funde del todo. Con el sol bajo y
	// detrás, la bruma se retira del cuerpo para que la cordillera quede en silueta contra el resplandor.
	float a_contraluz = sol_atras_ancho * (1.0 - smoothstep(0.1, 0.45, normalize(direccion_sol).y));
	color = mix(color, color_bruma * mix(1.0, 0.8, clamp(1.0 - fuerza_sol, 0.0, 1.0)), bruma * mix(1.0, 0.3, a_contraluz));
	ALBEDO = mix(color, color_bruma * brillo_pie, pie);
}
