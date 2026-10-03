class_name GameManager
extends Control

const CARD_SCENE := preload("res://scenes/card.tscn")

const POINTS_TO_WIN := 3
const NORMAL_ROUNDS := 5

const MAX_ENERGY := 10
const CHALLENGE_COST := 3
const DECISION_TIME := 15.0

var round_number := 1

var selected_card: CardData = null
var selected_card_disguised := false
var disguise_cost := 0

var player_1 := PlayerState.new()
var player_2 := PlayerState.new()

var tie_break_active := false
var tie_break_round := 0
var deck := Deck.new()

var player_card_views: Array[CardView] = []

var card_played := false
var player_1_played: CardData = null
var player_2_played: CardData = null

var decision_time_left: float = DECISION_TIME
var decision_active := false
var round_resolved := false
var game_over := false

@onready var player_hand: HBoxContainer = $PlayerHand
@onready var play_button: Button = $PlayButton
@onready var opponent_hand: HBoxContainer = $OpponentHand
@onready var player_2_play_button: Button = $Player2PlayButton

@onready var player_1_score_label: Label = $Player1Score
@onready var player_2_score_label: Label = $Player2Score
@onready var round_label: Label = $RoundLabel

@onready var disguise_button: Button = $DisguiseButton
@onready var disguise_panel: Panel = $DisguisePanel

@onready var player_1_energy_label: Label = $Player1Energy

@onready var disguise_buttons: Array[Button] = [
	$DisguisePanel/ButtonGrid/Button1,
	$DisguisePanel/ButtonGrid/Button2,
	$DisguisePanel/ButtonGrid/Button3,
	$DisguisePanel/ButtonGrid/Button4,
	$DisguisePanel/ButtonGrid/Button5,
	$DisguisePanel/ButtonGrid/Button6,
	$DisguisePanel/ButtonGrid/Button7,
	$DisguisePanel/ButtonGrid/Button8,
	$DisguisePanel/ButtonGrid/Button9
]

@onready var disguise_cancel_button: Button = $DisguisePanel/CancelButton

@onready var decision_panel: Panel = $DecisionPanel
@onready var decision_timer_label: Label = $DecisionPanel/DecisionTimerLabel
@onready var challenge_button: Button = $DecisionPanel/ChallengeButton
@onready var disclose_button: Button = $DecisionPanel/DiscloseButton


func _ready() -> void:
	print("OUTPLAY starting...")

	deck.shuffle()
	deal_starting_hands()

	print_hand("Player 1", player_1.hand)
	print_hand("Player 2", player_2.hand)

	print("Cards remaining in tie-break deck: ", deck.cards.size())

	player_2_play_button.pressed.connect(_on_player_2_play_button_pressed)
	play_button.pressed.connect(_on_play_button_pressed)

	disguise_button.pressed.connect(_on_disguise_button_pressed)
	disguise_cancel_button.pressed.connect(_on_disguise_cancel_pressed)

	challenge_button.pressed.connect(_on_challenge_pressed)
	disclose_button.pressed.connect(_on_disclose_pressed)

	for i in range(disguise_buttons.size()):
		disguise_buttons[i].pressed.connect(
			_on_disguise_target_pressed.bind(i + 1)
		)

	display_player_hand()
	display_opponent_hand()

	decision_panel.visible = false
	disguise_panel.visible = false

	update_ui()


func _process(delta: float) -> void:
	if not decision_active:
		return

	decision_time_left -= delta

	if decision_time_left <= 0.0:
		decision_time_left = 0.0
		update_decision_timer()

		print("===== DECISION TIME EXPIRED =====")

		end_decision_phase(true)
		return

	update_decision_timer()


func update_decision_timer() -> void:
	decision_timer_label.text = "%d" % ceili(decision_time_left)


func deal_starting_hands() -> void:
	for i in range(5):
		player_1.hand.append(deck.draw())
		player_2.hand.append(deck.draw())


func print_hand(player_name: String, hand: Array[CardData]) -> void:
	var values: Array[int] = []

	for card in hand:
		values.append(card.true_value)

	print(player_name, ": ", values)


func display_player_hand() -> void:
	for card_view in player_card_views:
		card_view.queue_free()

	player_card_views.clear()

	for card in player_1.hand:
		var card_view := CARD_SCENE.instantiate() as CardView

		player_hand.add_child(card_view)

		card_view.setup(card)
		card_view.hover_direction = -1.0

		card_view.card_selected.connect(_on_card_selected)

		player_card_views.append(card_view)


func display_opponent_hand() -> void:
	for child in opponent_hand.get_children():
		child.queue_free()

	for card in player_2.hand:
		var card_view := CARD_SCENE.instantiate() as CardView

		opponent_hand.add_child(card_view)

		card_view.setup_hidden(card)
		card_view.hover_direction = 1.0


func _on_card_selected(card: CardData) -> void:
	if game_over:
		return

	if card_played:
		return

	selected_card = card

	print("Selected card: ", card.displayed_value)

	update_disguise_button()


func _on_play_button_pressed() -> void:
	if game_over:
		return

	if selected_card == null:
		print("No card selected!")
		return

	if card_played:
		return

	card_played = true
	player_1_played = selected_card

	print("PLAYER 1 PLAYED CARD: ", selected_card.displayed_value)

	play_button.disabled = true

	# Player 1 has committed the card.
	disguise_button.disabled = true

	for button in disguise_buttons:
		button.disabled = true

	disguise_panel.visible = false


func _on_player_2_play_button_pressed() -> void:
	if game_over:
		return

	if player_2_played != null:
		return

	if player_2.hand.is_empty():
		return

	player_2_played = player_2.hand[0]

	print("PLAYER 2 PLAYED: ", player_2_played.displayed_value)

	player_2_play_button.disabled = true

	start_decision_phase()


func start_decision_phase() -> void:
	if game_over:
		return

	if player_1_played == null:
		return

	if player_2_played == null:
		return

	decision_active = true
	round_resolved = false
	decision_time_left = DECISION_TIME

	decision_panel.visible = true

	play_button.disabled = true
	player_2_play_button.disabled = true

	challenge_button.disabled = player_1.energy < CHALLENGE_COST

	var disclose_cost: int = get_disclose_cost()

	disclose_button.disabled = (
		not selected_card_disguised
		or player_1.energy < disclose_cost
	)

	update_decision_timer()

	print("===== DECISION PHASE =====")
	print("15 seconds to Challenge or Disclose")
	print("Challenge cost: ", CHALLENGE_COST)
	print("Disclose cost: ", disclose_cost)


func end_decision_phase(resolve_normal: bool = false) -> void:
	if not decision_active:
		return

	decision_active = false

	decision_panel.visible = false

	challenge_button.disabled = true
	disclose_button.disabled = true

	if resolve_normal:
		resolve_round()


func _on_challenge_pressed() -> void:
	if game_over:
		return

	if not decision_active:
		return

	if round_resolved:
		return

	if player_1.energy < CHALLENGE_COST:
		print("Not enough energy to challenge.")
		return

	# Lock the decision immediately.
	decision_active = false
	round_resolved = true

	decision_panel.visible = false
	challenge_button.disabled = true
	disclose_button.disabled = true

	player_1.energy -= CHALLENGE_COST

	print("===== CHALLENGE =====")
	print("P2 TRUE VALUE: ", player_2_played.true_value)
	print("P2 DISPLAYED VALUE: ", player_2_played.displayed_value)
	print("CHALLENGE COST: ", CHALLENGE_COST)

	var challenge_success: bool = (
		player_2_played.true_value != player_2_played.displayed_value
	)

	if challenge_success:
		print("CHALLENGE SUCCESS!")

		player_1.score += 1

		# Successful challenge returns the 3 energy reward.
		player_1.energy = mini(
			MAX_ENERGY,
			player_1.energy + 3
		)

		print("P1 SCORE: ", player_1.score)
		print("P1 ENERGY: ", player_1.energy)

	else:
		print("CHALLENGE FAILED!")

		player_2.score += 1

		player_2.energy = mini(
			MAX_ENERGY,
			player_2.energy + 3
		)

		print("P2 SCORE: ", player_2.score)
		print("P2 ENERGY: ", player_2.energy)

	finish_round()


func _on_disclose_pressed() -> void:
	if game_over:
		return

	if not decision_active:
		return

	if round_resolved:
		return

	if not selected_card_disguised:
		return

	var cost: int = get_disclose_cost()

	if player_1.energy < cost:
		print("Not enough energy to disclose.")
		return

	# Lock the decision immediately.
	decision_active = false
	round_resolved = true

	decision_panel.visible = false
	challenge_button.disabled = true
	disclose_button.disabled = true

	player_1.energy -= cost

	print("===== DISCLOSE =====")
	print("TRUE VALUE: ", selected_card.true_value)
	print("DISPLAYED VALUE: ", selected_card.displayed_value)
	print("DISCLOSE COST: ", cost)
	print("ENERGY REMAINING: ", player_1.energy)

	# Reveal the real card.
	selected_card.displayed_value = selected_card.true_value

	update_selected_card_visual()
	update_ui()

	resolve_round()


func resolve_round() -> void:
	if game_over:
		return

	if round_resolved == false:
		round_resolved = true

	if player_1_played == null:
		return

	if player_2_played == null:
		return

	print("----- ROUND RESULT -----")
	print("Player 1: ", player_1_played.displayed_value)
	print("Player 2: ", player_2_played.displayed_value)

	if card_beats(
		player_1_played.displayed_value,
		player_2_played.displayed_value
	):
		print("PLAYER 1 WINS ROUND!")

		player_1.score += 1

		player_1.energy = mini(
			MAX_ENERGY,
			player_1.energy + 3
		)

		player_2.energy = mini(
			MAX_ENERGY,
			player_2.energy + 2
		)

		print("P1 ENERGY: ", player_1.energy)
		print("P2 ENERGY: ", player_2.energy)

		finish_round()

	elif card_beats(
		player_2_played.displayed_value,
		player_1_played.displayed_value
	):
		print("PLAYER 2 WINS ROUND!")

		player_2.score += 1

		player_2.energy = mini(
			MAX_ENERGY,
			player_2.energy + 3
		)

		player_1.energy = mini(
			MAX_ENERGY,
			player_1.energy + 2
		)

		print("P1 ENERGY: ", player_1.energy)
		print("P2 ENERGY: ", player_2.energy)

		finish_round()

	else:
		print("TIE!")
		print("NO POINT")

		finish_round()

	update_ui()


func finish_round() -> void:
	if game_over:
		return

	if player_1.score >= POINTS_TO_WIN:
		end_game("PLAYER 1 WINS!")
		return

	if player_2.score >= POINTS_TO_WIN:
		end_game("PLAYER 2 WINS!")
		return

	remove_played_cards()

	if round_number >= NORMAL_ROUNDS:
		finish_five_rounds()
		return

	round_number += 1

	print("----- ROUND ", round_number, " -----")

	reset_round_state()
	update_ui()


func remove_played_cards() -> void:
	player_1.hand.erase(player_1_played)
	player_2.hand.erase(player_2_played)

	print("Player 1 cards remaining: ", player_1.hand.size())
	print("Player 2 cards remaining: ", player_2.hand.size())

	display_player_hand()
	display_opponent_hand()


func reset_round_state() -> void:
	selected_card = null
	selected_card_disguised = false
	disguise_cost = 0

	player_1_played = null
	player_2_played = null

	card_played = false

	decision_active = false
	round_resolved = false
	decision_time_left = DECISION_TIME

	play_button.disabled = false
	player_2_play_button.disabled = false

	decision_panel.visible = false
	disguise_panel.visible = false

	update_disguise_button()
	update_ui()


func finish_five_rounds() -> void:
	print("----- FIVE ROUNDS COMPLETE -----")
	print("FINAL SCORE: ", player_1.score, " : ", player_2.score)

	if player_1.score > player_2.score:
		end_game("PLAYER 1 WINS!")

	elif player_2.score > player_1.score:
		end_game("PLAYER 2 WINS!")

	else:
		print("SCORE TIED!")
		start_tie_break()


func start_tie_break() -> void:
	tie_break_active = true
	tie_break_round = 0

	print("===== TIE-BREAK =====")

	play_tie_break()


func play_tie_break() -> void:
	tie_break_round += 1

	print("----- TIE-BREAK ", tie_break_round, " -----")

	if deck.cards.size() < 2:
		end_game("DRAW GAME")
		return

	var player_1_tie_card: CardData = deck.draw()
	var player_2_tie_card: CardData = deck.draw()

	print("P1 TIE-BREAK CARD: ", player_1_tie_card.true_value)
	print("P2 TIE-BREAK CARD: ", player_2_tie_card.true_value)

	if card_beats(
		player_1_tie_card.true_value,
		player_2_tie_card.true_value
	):
		print("PLAYER 1 WINS TIE-BREAK!")
		end_game("PLAYER 1 WINS!")

	elif card_beats(
		player_2_tie_card.true_value,
		player_1_tie_card.true_value
	):
		print("PLAYER 2 WINS TIE-BREAK!")
		end_game("PLAYER 2 WINS!")

	else:
		print("TIE AGAIN!")
		play_tie_break()


func end_game(result: String) -> void:
	if game_over:
		return

	game_over = true
	decision_active = false
	tie_break_active = false

	decision_panel.visible = false
	disguise_panel.visible = false

	print("========================")
	print("       GAME OVER")
	print(result)
	print("========================")

	play_button.disabled = true
	player_2_play_button.disabled = true
	disguise_button.disabled = true
	challenge_button.disabled = true
	disclose_button.disabled = true

	for button in disguise_buttons:
		button.disabled = true


func card_beats(attacker: int, defender: int) -> bool:
	# Assassin beats King.
	if attacker == 1 and defender == 9:
		return true

	# King does not beat Assassin.
	if attacker == 9 and defender == 1:
		return false

	return attacker > defender


func update_ui() -> void:
	player_1_score_label.text = "PLAYER 1  |  SCORE: %d" % player_1.score
	player_2_score_label.text = "PLAYER 2  |  SCORE: %d" % player_2.score
	round_label.text = "ROUND %d" % round_number

	player_1_energy_label.text = "ENERGY: %d / %d" % [
		player_1.energy,
		MAX_ENERGY
	]


func calculate_disguise_cost(current_value: int, target_value: int) -> int:
	var cost: int = abs(target_value - current_value)

	if target_value == 1 or target_value == 9:
		cost = max(cost, 2)

	return cost


func can_disguise(card: CardData) -> bool:
	if card == null:
		return false

	if card.true_value == 9:
		return false

	if card_played:
		return false

	return true


func can_disguise_to(card: CardData, target_value: int) -> bool:
	if card == null:
		return false

	if card.true_value == 9:
		return false

	if card_played:
		return false

	if target_value < 1 or target_value > 9:
		return false

	if target_value == card.true_value:
		return false

	var cost: int = calculate_disguise_cost(
		card.true_value,
		target_value
	)

	if player_1.energy < cost:
		return false

	return true


func _on_disguise_button_pressed() -> void:
	if game_over:
		return

	if card_played:
		return

	if selected_card == null:
		print("Select a card first.")
		return

	if not can_disguise(selected_card):
		print("This card cannot be disguised.")
		return

	update_disguise_menu()

	disguise_panel.visible = true


func update_disguise_menu() -> void:
	if selected_card == null:
		return

	for target_value in range(1, 10):
		var button: Button = disguise_buttons[target_value - 1]

		var allowed: bool = can_disguise_to(
			selected_card,
			target_value
		)

		button.disabled = not allowed

		if allowed:
			var cost: int = calculate_disguise_cost(
				selected_card.true_value,
				target_value
			)

			button.text = "%d  (%dE)" % [target_value, cost]
		else:
			button.text = "%d  (X)" % target_value


func _on_disguise_target_pressed(target_value: int) -> void:
	if game_over:
		return

	if card_played:
		print("Cannot disguise after playing.")
		return

	if selected_card == null:
		return

	if not can_disguise_to(selected_card, target_value):
		print("Cannot disguise.")
		return

	disguise_cost = calculate_disguise_cost(
		selected_card.true_value,
		target_value
	)

	player_1.energy -= disguise_cost

	selected_card.displayed_value = target_value
	selected_card_disguised = true

	print("----- DISGUISE -----")
	print("TRUE VALUE: ", selected_card.true_value)
	print("DISPLAYED VALUE: ", selected_card.displayed_value)
	print("COST: ", disguise_cost)
	print("ENERGY: ", player_1.energy)

	disguise_panel.visible = false

	update_selected_card_visual()
	update_disguise_button()
	update_ui()


func update_selected_card_visual() -> void:
	for card_view in player_card_views:
		if card_view.card_data == selected_card:
			card_view.refresh_visual()
			break


func _on_disguise_cancel_pressed() -> void:
	disguise_panel.visible = false


func update_disguise_button() -> void:
	if game_over:
		disguise_button.disabled = true
		return

	if selected_card == null:
		disguise_button.disabled = true
		return

	if card_played:
		disguise_button.disabled = true
		return

	if selected_card.true_value == 9:
		disguise_button.disabled = true
		return

	disguise_button.disabled = player_1.energy <= 0


func get_disclose_cost() -> int:
	if not selected_card_disguised:
		return 0

	return maxi(
		1,
		ceili(float(disguise_cost) / 2.0)
	)
