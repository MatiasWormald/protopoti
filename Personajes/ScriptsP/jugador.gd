extends CharacterBody3D

@export var velocidad: float = 5.0
@export var velocidad_correr: float = 9.0
@export var fuerza_salto: float = 5.0
@export var gravedad: float = 9.8
@export var sensibilidad_mouse: float = 0.003
@export var intervalo_afk: float = 30.0
@export var velocidad_giro: float = 10.0
@export var mover_al_atacar: bool = true

# Zoom de cámara
@export var zoom_min: float = 1.5
@export var zoom_max: float = 8.0
@export var zoom_paso: float = 0.5
@export var zoom_suavidad: float = 10.0

# ---------------------------------------------------------
# COMBO
# ---------------------------------------------------------

# Cuánto antes del golpe podemos presionar el siguiente ataque.
# 0.20 = aproximadamente 5 frames antes a 24 FPS.
@export var ventana_buffer_combo: float = 0.20

# Mezcla entre animaciones de ataque.
@export var mezcla_ataques: float = 0.06

const FPS_ANIMACION := 24.0

# Attack01
const ATTACK01_HIT := 23.0 / FPS_ANIMACION
const ATTACK01_FIN := 35.0 / FPS_ANIMACION

# Attack02
const ATTACK02_HIT := 12.0 / FPS_ANIMACION
const ATTACK02_FIN := 30.0 / FPS_ANIMACION

# Attack03
const ATTACK03_HIT := 18.0 / FPS_ANIMACION
const ATTACK03_FIN := 30.0 / FPS_ANIMACION


# ---------------------------------------------------------
# SALTO
# ---------------------------------------------------------

const TIEMPO_COYOTE := 0.1
const TIEMPO_BUFFER := 0.1


# ---------------------------------------------------------
# NOMBRES DE ANIMACIONES
# ---------------------------------------------------------

const ANIM_IDLE := "AFK"
const ANIM_CAMINAR := "Caminar"
const ANIM_CORRER := "Correr"
const ANIM_SALTO := "Salto"
const ANIM_AFK := "Idle"

const ANIM_ATAQUE_1 := "Attack01"
const ANIM_ATAQUE_2 := "Attack02"
const ANIM_ATAQUE_3 := "Attack03"


# ---------------------------------------------------------
# REFERENCIAS
# ---------------------------------------------------------

@onready var modelo: Node3D = $PersonajeT001
@onready var animation_player: AnimationPlayer = $PersonajeT001/AnimationPlayer
@onready var pivote_camara: Node3D = $PivoteCamara
@onready var brazo_camara: SpringArm3D = $PivoteCamara/SpringArm3D


# ---------------------------------------------------------
# VARIABLES GENERALES
# ---------------------------------------------------------

var zoom_objetivo: float = 4.0

var tiempo_quieto := 0.0
var tiempo_coyote := 0.0
var buffer_salto := 0.0

var animacion_actual := ""

var en_aire := false
var atacando := false
var afk_reproduciendo := false


# ---------------------------------------------------------
# VARIABLES DEL COMBO
# ---------------------------------------------------------

# 0 = no está atacando
# 1 = Attack01
# 2 = Attack02
# 3 = Attack03
var combo_actual := 0

# Guarda un click para el siguiente ataque
var ataque_en_buffer := false


func _ready() -> void:

	$PivoteCamara/SpringArm3D/Camera3D.current = true

	# Evita que la cámara choque con el propio jugador
	brazo_camara.add_excluded_object(get_rid())
	brazo_camara.spring_length = zoom_objetivo

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


	# -----------------------------------------------------
	# ANIMACIONES EN BUCLE
	# -----------------------------------------------------

	for nombre in [
		ANIM_IDLE,
		ANIM_CAMINAR,
		ANIM_CORRER
	]:
		if animation_player.has_animation(nombre):
			animation_player.get_animation(nombre).loop_mode = Animation.LOOP_LINEAR


	# -----------------------------------------------------
	# ANIMACIONES DE UNA SOLA EJECUCIÓN
	# -----------------------------------------------------

	for nombre in [
		ANIM_SALTO,
		ANIM_AFK,
		ANIM_ATAQUE_1,
		ANIM_ATAQUE_2,
		ANIM_ATAQUE_3
	]:
		if animation_player.has_animation(nombre):
			animation_player.get_animation(nombre).loop_mode = Animation.LOOP_NONE


	animation_player.animation_finished.connect(_on_animacion_terminada)


	# Mostrar las animaciones disponibles
	print("Animaciones disponibles: ", animation_player.get_animation_list())


# ---------------------------------------------------------
# INPUT
# ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:

	# -----------------------------------------------------
	# ATAQUE
	# -----------------------------------------------------

	if event.is_action_pressed("attack") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_solicitar_ataque()
		return


	# -----------------------------------------------------
	# CÁMARA
	# -----------------------------------------------------

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:

		pivote_camara.rotate_y(
			-event.relative.x * sensibilidad_mouse
		)

		pivote_camara.rotation.x = clamp(
			pivote_camara.rotation.x
				- event.relative.y * sensibilidad_mouse,
			deg_to_rad(-80),
			deg_to_rad(50)
		)


	# -----------------------------------------------------
	# MOUSE
	# -----------------------------------------------------

	if event is InputEventMouseButton and event.pressed:

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:

			zoom_objetivo = clamp(
				zoom_objetivo - zoom_paso,
				zoom_min,
				zoom_max
			)

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:

			zoom_objetivo = clamp(
				zoom_objetivo + zoom_paso,
				zoom_min,
				zoom_max
			)

		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


	# -----------------------------------------------------
	# ESCAPE
	# -----------------------------------------------------

	if event is InputEventKey and event.pressed:

		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------
# FÍSICA
# ---------------------------------------------------------

func _physics_process(delta: float) -> void:

	# -----------------------------------------------------
	# ZOOM
	# -----------------------------------------------------

	brazo_camara.spring_length = lerp(
		brazo_camara.spring_length,
		zoom_objetivo,
		zoom_suavidad * delta
	)


	# -----------------------------------------------------
	# GRAVEDAD
	# -----------------------------------------------------

	if not is_on_floor():

		velocity.y -= gravedad * delta
		tiempo_coyote -= delta

	else:

		velocity.y = 0.0
		tiempo_coyote = TIEMPO_COYOTE


	# -----------------------------------------------------
	# SALTO
	# -----------------------------------------------------

	if Input.is_action_just_pressed("jump"):

		buffer_salto = TIEMPO_BUFFER

	else:

		buffer_salto -= delta


	# No permitir salto durante el ataque
	if not atacando:

		if buffer_salto > 0.0 and tiempo_coyote > 0.0:

			velocity.y = fuerza_salto

			buffer_salto = 0.0
			tiempo_coyote = 0.0


	# -----------------------------------------------------
	# MOVIMIENTO
	# -----------------------------------------------------

	var input_dir := Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_backward"
	)


	var yaw := Basis(
		Vector3.UP,
		pivote_camara.global_rotation.y
	)


	var direccion := (
		yaw * Vector3(
			input_dir.x,
			0.0,
			input_dir.y
		)
	).normalized()


	var moviendo := direccion.length() > 0.0


	# -----------------------------------------------------
	# CORRER
	# -----------------------------------------------------

	var corriendo := (
		moviendo
		and Input.is_action_pressed("run")
	)


	var vel_actual := (
		velocidad_correr
		if corriendo
		else velocidad
	)


	# Si mover_al_atacar está desactivado,
	# el personaje se queda quieto durante el ataque.
	if atacando and not mover_al_atacar:

		vel_actual = 0.0


	velocity.x = direccion.x * vel_actual
	velocity.z = direccion.z * vel_actual


	# -----------------------------------------------------
	# GIRAR PERSONAJE
	# -----------------------------------------------------

	if moviendo:

		var angulo := atan2(
			direccion.x,
			direccion.z
		)

		modelo.rotation.y = lerp_angle(
			modelo.rotation.y,
			angulo,
			velocidad_giro * delta
		)


	# -----------------------------------------------------
	# COMPROBAR COMBO
	# -----------------------------------------------------

	if atacando:

		_procesar_combo()


	# -----------------------------------------------------
	# ANIMACIONES NORMALES
	# -----------------------------------------------------

	_actualizar_animacion(
		moviendo,
		corriendo,
		delta
	)


	move_and_slide()


# ---------------------------------------------------------
# SOLICITAR ATAQUE
# ---------------------------------------------------------

func _solicitar_ataque() -> void:

	# -----------------------------------------------------
	# PRIMER ATAQUE
	# -----------------------------------------------------

	if not atacando:

		# No atacar en el aire
		if not is_on_floor():
			return

		# Comprobar que exista
		if not animation_player.has_animation(ANIM_ATAQUE_1):

			push_warning(
				"No existe la animación '%s'. Disponibles: %s"
				% [
					ANIM_ATAQUE_1,
					animation_player.get_animation_list()
				]
			)

			return


		atacando = true
		combo_actual = 1
		ataque_en_buffer = false

		afk_reproduciendo = false
		tiempo_quieto = 0.0

		animacion_actual = ""

		_reproducir_ataque(ANIM_ATAQUE_1)

		print("COMBO: Attack01")

		return


	# -----------------------------------------------------
	# SI YA ESTÁ ATACANDO
	# -----------------------------------------------------

	# Si ya estamos en Attack03,
	# no existe un cuarto ataque.
	if combo_actual >= 3:
		return


	var posicion_actual := animation_player.current_animation_position


	# -----------------------------------------------------
	# ATTACK01
	# -----------------------------------------------------

	if combo_actual == 1:

		# Solo aceptamos el click cerca del momento
		# en que Attack01 llega al frame 23.
		if posicion_actual >= ATTACK01_HIT - ventana_buffer_combo \
		and posicion_actual < ATTACK01_HIT:

			ataque_en_buffer = true

			print("Attack02 preparado")


	# -----------------------------------------------------
	# ATTACK02
	# -----------------------------------------------------

	elif combo_actual == 2:

		# Attack02 llega al frame 12
		# y desde ahí puede pasar a Attack03.
		if posicion_actual >= ATTACK02_HIT - ventana_buffer_combo \
		and posicion_actual < ATTACK02_HIT:

			ataque_en_buffer = true

			print("Attack03 preparado")


# ---------------------------------------------------------
# PROCESAR COMBO
# ---------------------------------------------------------

func _procesar_combo() -> void:

	var posicion_actual := animation_player.current_animation_position


	# -----------------------------------------------------
	# ATTACK01
	# -----------------------------------------------------

	if combo_actual == 1:

		# Llegamos al frame 23.
		if posicion_actual >= ATTACK01_HIT:

			if ataque_en_buffer:

				_iniciar_siguiente_ataque(2)

				return


		# Si no hubo segundo click,
		# dejamos que Attack01 llegue al frame 35.
		if posicion_actual >= ATTACK01_FIN:

			_terminar_combo()

			return


	# -----------------------------------------------------
	# ATTACK02
	# -----------------------------------------------------

	elif combo_actual == 2:

		# Llegamos al frame 12.
		if posicion_actual >= ATTACK02_HIT:

			if ataque_en_buffer:

				_iniciar_siguiente_ataque(3)

				return


		# Si no hubo tercer click,
		# dejamos terminar Attack02.
		if posicion_actual >= ATTACK02_FIN:

			_terminar_combo()

			return


	# -----------------------------------------------------
	# ATTACK03
	# -----------------------------------------------------

	elif combo_actual == 3:

		# Attack03 termina en frame 30.
		if posicion_actual >= ATTACK03_FIN:

			_terminar_combo()

			return


# ---------------------------------------------------------
# INICIAR SIGUIENTE ATAQUE
# ---------------------------------------------------------

func _iniciar_siguiente_ataque(numero: int) -> void:

	ataque_en_buffer = false
	combo_actual = numero


	if numero == 2:

		_reproducir_ataque(ANIM_ATAQUE_2)

		print("COMBO: Attack01 -> Attack02")


	elif numero == 3:

		_reproducir_ataque(ANIM_ATAQUE_3)

		print("COMBO: Attack02 -> Attack03")


# ---------------------------------------------------------
# TERMINAR COMBO
# ---------------------------------------------------------

func _terminar_combo() -> void:

	atacando = false
	combo_actual = 0
	ataque_en_buffer = false

	animacion_actual = ""

	print("COMBO TERMINADO")


# ---------------------------------------------------------
# ANIMACIONES NORMALES
# ---------------------------------------------------------

func _actualizar_animacion(
	moviendo: bool,
	corriendo: bool,
	delta: float
) -> void:

	# Mientras ataca,
	# no cambiar la animación.
	if atacando:
		return


	# -----------------------------------------------------
	# SALTO
	# -----------------------------------------------------

	if not is_on_floor():

		tiempo_quieto = 0.0
		afk_reproduciendo = false

		if not en_aire:

			en_aire = true

			_reproducir(ANIM_SALTO)

		return


	en_aire = false


	# -----------------------------------------------------
	# MOVIMIENTO
	# -----------------------------------------------------

	if moviendo:

		tiempo_quieto = 0.0
		afk_reproduciendo = false

		if corriendo:

			_reproducir(ANIM_CORRER)

		else:

			_reproducir(ANIM_CAMINAR)

		return


	# -----------------------------------------------------
	# QUIETO
	# -----------------------------------------------------

	if afk_reproduciendo:
		return


	_reproducir(ANIM_IDLE)

	tiempo_quieto += delta


	# -----------------------------------------------------
	# AFK
	# -----------------------------------------------------

	if tiempo_quieto >= intervalo_afk:

		afk_reproduciendo = true

		_reproducir(ANIM_AFK)


# ---------------------------------------------------------
# ANIMACIÓN TERMINADA
# ---------------------------------------------------------

func _on_animacion_terminada(nombre: StringName) -> void:

	# Attack01
	if nombre == ANIM_ATAQUE_1:

		# Si por alguna razón no hubo combo,
		# terminamos el ataque.
		if combo_actual == 1:

			_terminar_combo()


	# Attack02
	elif nombre == ANIM_ATAQUE_2:

		if combo_actual == 2:

			_terminar_combo()


	# Attack03
	elif nombre == ANIM_ATAQUE_3:

		if combo_actual == 3:

			_terminar_combo()


	# AFK
	elif nombre == ANIM_AFK:

		afk_reproduciendo = false
		tiempo_quieto = 0.0
		animacion_actual = ""


# ---------------------------------------------------------
# REPRODUCIR ATAQUE
# ---------------------------------------------------------

func _reproducir_ataque(nombre: String) -> void:

	if not animation_player.has_animation(nombre):
		return

	animacion_actual = nombre

	# Mezcla muy corta para que no destruya
	# la pose de inicio del siguiente ataque.
	animation_player.play(
		nombre,
		mezcla_ataques
	)


# ---------------------------------------------------------
# REPRODUCIR ANIMACIÓN NORMAL
# ---------------------------------------------------------

func _reproducir(nombre: String) -> void:

	if animacion_actual != nombre \
	and animation_player.has_animation(nombre):

		animacion_actual = nombre

		animation_player.play(
			nombre,
			0.2
		)
