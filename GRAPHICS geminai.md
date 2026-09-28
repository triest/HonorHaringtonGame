### Task for Claude: Implement the Impeller Wedge Spatial Shader
Please implement a custom 3D shader for the Impeller Wedge mesh in Godot 4.3. 
The shader must read the screen texture to distort background space (gravitational lensing) and support dynamic hit flashes using a uniform parameter.

#### Godot 4.3 Spatial Shader Code (`impeller_wedge.gdshader`):

```glsl
shader_type spatial;
render_mode render_priority 10, depth_draw_never, cull_disabled, unshaded;

// Текстура экрана для создания эффекта преломления (искажения)
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Настройки искажения пространства
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.03;
uniform float wave_speed = 2.0;
uniform float wave_frequency = 10.0;

// Настройки базового свечения клина
uniform vec4 wedge_base_color : source_color = vec4(0.1, 0.4, 1.0, 0.2);
uniform float edge_intensity : hint_range(0.1, 5.0) = 2.0;

// Параметры динамической вспышки при попадании
uniform vec3 hit_location = vec3(0.0); // Локальные координаты попадания
uniform vec4 hit_color : source_color = vec4(1.0, 0.3, 0.1, 1.0);
uniform float hit_radius = 1.5;
uniform float hit_intensity : hint_range(0.0, 10.0) = 0.0; // Анимируется через GDScript (вспышка и затухание)

varying vec3 local_pos;

void vertex() {
    // Передаем локальные координаты вершин во фрагментный шейдер для расчета точки попадания
    local_pos = VERTEX;
}

void fragment() {
    // 1. Эффект Френеля (свечение по краям геометрии клина)
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), edge_intensity);
    
    // 2. Расчет искажения пространства (гравитационное линзирование)
    // Создаем волновой паттерн, симулирующий нестабильность гравитационного поля
    float wave = sin(NODE_POSITION_WORLD.x + TIME * wave_speed) * cos(NODE_POSITION_WORLD.z + TIME * wave_speed);
    vec2 distortion = vec2(wave) * distortion_strength;
    
    // Читаем пиксели экрана со смещением (преломление заднего фона)
    vec4 screen_color = texture(screen_texture, SCREEN_UV + distortion);
    
    // 3. Расчет зоны попадания (Hit Flash)
    float dist_to_hit = distance(local_pos, hit_location);
    float hit_pulse = smoothstep(hit_radius, 0.0, dist_to_hit);
    vec4 final_hit_effect = hit_color * hit_pulse * hit_intensity;
    
    // 4. Финальное смешивание (Борта клина светятся, центр прозрачный + искажает)
    vec3 base_glow = wedge_base_color.rgb * fresnel * 2.0; // Умножаем на 2 для HDR-свечения (Glow)
    
    ALBEDO = screen_color.rgb + base_glow + final_hit_effect.rgb;
    ALPHA = clamp(wedge_base_color.a + fresnel + (hit_pulse * hit_intensity), 0.0, 1.0);
}
```

#### How to apply this in Godot 4.3:
1. Create a `MeshInstance3D` in the ship scene representing the upper or lower wedge boundary (e.g., a slightly curved plane or flat disk).
2. Create a new `ShaderMaterial`, paste the code above.
3. To trigger a hit effect from the `simulation` loop, pass the impact point converted to the wedge's local space and animate `hit_intensity` from high to low using a `Tween` or a simple timer.
