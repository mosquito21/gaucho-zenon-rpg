// La bruma de lejos del piso y de las copas de los árboles. La usan terreno.gdshader y hoja.tres
// (con #include), para que la cuenta esté en un solo lugar.
//
// Por qué no alcanza con la niebla del ambiente: esa borra por igual todo lo que está a más de
// 1.100 m. El macizo del paso a Chile desaparecía y, al tapar el pie de la cordillera del fondo,
// la dejaba flotando. Acá se hace la misma cuenta que la niebla del ambiente, pero con un tope
// para lo que está alto: el pie del cerro se pierde en la bruma y el cuerpo asoma por arriba.
//
// Todos estos valores los pone scripts/CicloDiaNoche.gd a cada momento (los tres últimos salen de
// su grupo "Bruma de lejos"). Los que quedan escritos acá son los del mediodía: lo que ve el editor.
uniform vec3 u_bruma_color : source_color = vec3(0.67, 0.75, 0.75);
// color del resplandor del lado del sol y, en el cuarto número, cuánto pesa (0 = nada)
uniform vec4 u_bruma_resplandor : source_color = vec4(1.0, 0.6, 0.3, 0.0);
uniform vec3 u_bruma_sol = vec3(0.0, 1.0, 0.0);
// a qué distancia empieza, a cuál llega al máximo, la curva y el máximo (como en el ambiente)
uniform vec4 u_bruma = vec4(90.0, 1100.0, 0.85, 1.0);
// cuánta bruma tapa las cumbres como mucho, y entre qué alturas el suelo pasa de llano a cumbre
uniform float u_bruma_cumbres : hint_range(0.0, 1.0) = 0.3;
uniform float u_bruma_baja = 10.0;
uniform float u_bruma_alta = 70.0;

// vertice_vista: el punto visto desde la cámara (VERTEX en fragment); altura: su altura en el mundo.
// Devuelve el color de la bruma y, en el cuarto número, cuánto tapa. Se asigna a FOG.
vec4 bruma_del_mundo(vec3 vertice_vista, float altura, mat4 vista_inversa) {
	float cantidad = pow(smoothstep(u_bruma.x, u_bruma.y, length(vertice_vista)), u_bruma.z) * u_bruma.w;
	cantidad = min(cantidad, mix(1.0, u_bruma_cumbres, smoothstep(u_bruma_baja, u_bruma_alta, altura)));
	// El color es el del horizonte y, del lado del sol, el del resplandor: igual que en el cielo.
	vec3 hacia = (vista_inversa * vec4(normalize(vertice_vista), 0.0)).xyz;
	float lado_sol = pow(clamp(dot(hacia, u_bruma_sol) * 0.5 + 0.5, 0.0, 1.0), 3.0);
	return vec4(mix(u_bruma_color, u_bruma_resplandor.rgb, u_bruma_resplandor.a * lado_sol), cantidad);
}
