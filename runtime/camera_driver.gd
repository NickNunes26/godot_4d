## Drives a Camera3D from a CameraTrack as TimelineController.current_day
## advances. Movie mode only -- SequenceManager creates one exactly when a
## recording run has a non-empty track, so an interactive session's free-fly
## camera is never touched, which is the point: free-fly is how clashes get
## inspected.
##
## The two never fight over the same node, because they are never both live:
## _start_movie_run() disables free_look_camera.gd's _process/_unhandled_input
## before this is created (see SequenceManager._disable_free_look()).
##
## Reads current_day rather than accumulating its own clock, so the camera is
## locked to the same virtual time as the geometry by construction -- including
## under Movie Maker's fixed synthetic delta, which makes the camera move
## deterministic for free rather than needing its own frame-rate handling.
@tool
class_name CameraDriver
extends Node

var _track: CameraTrack = null
var _controller: TimelineController = null
var _camera: Camera3D = null
## The camera's own fov at setup, used for any keyframe that doesn't specify
## one -- so a track authored without thinking about fov leaves the scene's
## framing alone instead of snapping to some default.
var _base_fov: float = 75.0

func setup(track: CameraTrack, controller: TimelineController, camera: Camera3D) -> void:
	_track = track
	_controller = controller
	_camera = camera
	if _camera:
		_base_fov = _camera.fov
	# Apply immediately: _process() doesn't run until the next frame, and in a
	# recording that frame is already in the video -- the first frame would
	# otherwise show the scene's authored camera position before snapping to
	# the track's opening shot.
	_apply()

func _process(_delta: float) -> void:
	_apply()

func _apply() -> void:
	if not _track or not _controller or not is_instance_valid(_camera):
		return
	var pose := _track.sample(_controller.current_day)
	if pose.is_empty():
		return
	_camera.global_transform = Transform3D(pose.basis, pose.position)
	_camera.fov = pose.fov if pose.fov != null else _base_fov
