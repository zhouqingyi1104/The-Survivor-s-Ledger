shader_type spatial;
render_mode specular_schlick_ggx;

varying vec2 bank_pos;
void vertex() {
	bank_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xz;
}
void fragment() {
	vec2 p=bank_pos;
	float ripple=sin(p.x*3.5+p.y*2.7+TIME*1.3+1.7*sin(p.x*0.56));
	float crosswave=sin(p.x*7.8-p.y*1.7+TIME*0.81);
	float shoal=smoothstep(1.65,3.10,abs(p.y-5.0));
	ALBEDO=mix(vec3(.032,.094,.100),vec3(.084,.122,.104),shoal);
	NORMAL=normalize(NORMAL+mat3(VIEW_MATRIX)*vec3(.048*ripple,0,.037*crosswave));
	ROUGHNESS=0.24+shoal*.10;
	SPECULAR=0.76;
}
