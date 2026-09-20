# Engine decision

The first executable milestone uses original Swift with SceneKit so rendering, collision, touch input, bots, round logic, Simulator execution, and unsigned ARM64 packaging can be validated immediately without proprietary assets.

This is an interim runtime and does not by itself satisfy the final open-source-engine requirement. The next integration decision is Xash3D FWGS versus ioquake3/OpenArena-derived code, with the selected engine consuming the engine-neutral intermediate asset format.
