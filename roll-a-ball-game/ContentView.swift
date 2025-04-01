import SwiftUI
import RealityKit
import Combine



enum ForceDirection {
    case up,left,right,down
    
    var symbol: String{
        switch self {
        case .up:
            return "arrow.up.circle.fill"
        case .left:
            return "arrow.left.circle.fill"
        case .right:
            return "arrow.right.circle.fill"
        case .down:
            return "arrow.down.circle.fill"
        }
    }
    
    var vector: SIMD3<Float>{
        switch self{
        case .up:
            return SIMD3<Float>(0,0,-1)
        case .down:
            return SIMD3<Float>(0,0,1)
        case .left:
            return SIMD3<Float>(-1,0,0)
        case .right:
            return SIMD3<Float>(1,0,0)
        }
    }
}

struct ContentView : View {
    
    @State var showGameOver: Bool = false
    
    private let arView =  ARGameView()
    var body: some View {
        ZStack{
            
            ARViewContainer(arView: arView)
                .edgesIgnoringSafeArea(.all)
            ControlsView(
                startApplyingForce: arView.startApplyingForce(direction:),
                stopApplyingForce: arView.stopApplyingForce
            )
            
        }.alert(isPresented: $showGameOver){
            Alert(
                title: Text("You Win!"),
                dismissButton: .default(Text("Ok")){
                    showGameOver = false
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: PinSystem.gameOverNotification)){ _ in
            showGameOver = true
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    
    let arView: ARGameView
    

    func makeUIView(context: Context) -> ARGameView {
        
            // Create a floor entity
            let floorMesh = MeshResource.generatePlane(width: 100, depth: 100)
            // Use a clear color to make the floor invisible
            let floorMaterial = SimpleMaterial(color: .clear, isMetallic: false)
            let floorEntity = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
            
            // Generate collision shapes for the floor
            floorEntity.generateCollisionShapes(recursive: false)
            
            // Attach a static physics body to the floor so it remains immovable
            floorEntity.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
                massProperties: .default,
                material: .default,
                mode: .static
            )
            
            // Create an anchor for the floor and add it to the scene
            let floorAnchor = AnchorEntity(plane: .horizontal)
            floorAnchor.addChild(floorEntity)
            arView.scene.addAnchor(floorAnchor)

            // Asynchronously load the USDZ model
            Task {
                do {
                    let rollABall = try await Entity(named: "ballpin_scene1")
                    
                    // Create an anchor entity
                    let anchorEntity = AnchorEntity(plane: .horizontal)
                    
                    // Setup your custom components in the model entity
                    setupComponents(in: rollABall)
                    
                    // Add the model to the anchor and then to the AR scene
                    anchorEntity.addChild(rollABall)
                    arView.scene.addAnchor(anchorEntity)
                    
                    
                } catch {
                    print("Error loading model: \(error.localizedDescription)")
                }
            }
        
        
        return arView
    }
    
    private func setupComponents(in rollABall: Entity) {
        rollABall.descendants.forEach { entity in
            print("Found descendant entity: \(entity.name)")
        }
        
        let ballPhysicsMaterial = PhysicsMaterialResource.generate(friction: 0.5, restitution: 0.3)
        let pinPhysicsMaterial = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.1)

        // Setup the ball
        if let ball = rollABall.findEntity(named: "ball") as? ModelEntity {
            print("BALL FOUND YAYYYYYYYY, initial coordinates: \(ball.transform.translation)")
            // Apply a blue material so it's visually distinct.
            let ballMaterial = SimpleMaterial(color: .blue, isMetallic: false)
            ball.model?.materials = [ballMaterial]
            
            ball.components[BallComponent.self] = BallComponent()
            if ball.components[PhysicsBodyComponent.self] == nil {
                print("Ball missing physics body, adding one...")
                ball.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
                    massProperties: .default,
                    material: ballPhysicsMaterial,
                    mode: .dynamic
                )
                print("Added physics body to ball")
            }
            // Generate collision shapes (optional)
            ball.generateCollisionShapes(recursive: true)
            // Explicitly create a CollisionComponent using a sphere shape.
            let bounds = ball.visualBounds(relativeTo: ball)
            let radius = max(bounds.extents.x, bounds.extents.y, bounds.extents.z) / 2.0
            ball.components[CollisionComponent.self] = CollisionComponent(
                shapes: [ShapeResource.generateSphere(radius: radius)]
            )
            print("Added CollisionComponent to ball with radius: \(radius)")
        } else {
            print("Entity named 'ball' not found in the USDZ model")
        }
        
        // Setup the pins
        let pinEntities = rollABall.descendants.filter { $0.name.lowercased().hasPrefix("pin") }
        print("Number of pin entities detected: \(pinEntities.count)")

        pinEntities.forEach { pin in
            print("Initial coordinates for pin \(pin.name): \(pin.transform.translation)")
            pin.components[PinComponent.self] = PinComponent()
            if pin.components[PhysicsBodyComponent.self] == nil {
                print("Pin \(pin.name) missing physics body, adding one...")
                pin.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
                    massProperties: .default,
                    material: pinPhysicsMaterial,
                    mode: .dynamic  // Use dynamic so the pins react to collisions.
                )
                print("Added physics body to \(pin.name)")
            }
            // Generate collision shapes (optional)
            pin.generateCollisionShapes(recursive: true)
            // Explicitly add a CollisionComponent.
//            if let modelEntity = pin as? ModelEntity {
//                let bounds = modelEntity.visualBounds(relativeTo: modelEntity)
//                // Use a box shape based on the pin's extents.
//                let size = bounds.extents
//                pin.components[CollisionComponent.self] = CollisionComponent(
//                    shapes: [ShapeResource.generateBox(size: size)]
//                )
//                print("Added CollisionComponent to pin \(pin.name) with size: \(size)")
//            }
            if let modelEntity = pin as? ModelEntity {
                // Use the pin directly if it's a ModelEntity.
                let bounds = modelEntity.visualBounds(relativeTo: modelEntity)
                let size = bounds.extents
                pin.components[CollisionComponent.self] = CollisionComponent(
                    shapes: [ShapeResource.generateBox(size: size)]
                )
                print("Added CollisionComponent to pin \(pin.name) with size: \(size)")
            } else if let childModel = pin.descendants.first(where: { $0 is ModelEntity }) as? ModelEntity {
                // Otherwise, use the first descendant ModelEntity.
                let bounds = childModel.visualBounds(relativeTo: childModel)
                let size = bounds.extents
                pin.components[CollisionComponent.self] = CollisionComponent(
                    shapes: [ShapeResource.generateBox(size: size)]
                )
                print("Added CollisionComponent to pin \(pin.name) (via descendant) with size: \(size)")
            } else {
                print("Pin \(pin.name) does not contain a ModelEntity for collision shape.")
            }

        }
    }

    
    func updateUIView(_ uiView: ARGameView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var cancellable: AnyCancellable?
    }
}

struct BallComponent: Component {
    static let query = EntityQuery(where: .has(BallComponent.self))
    
    var direction: ForceDirection?
}

class PinSystem: System {
    static let gameOverNotification = Notification.Name("GameOver")
    required init(scene: RealityKit.Scene){}
    func update(context: SceneUpdateContext) {
        let pins = context.scene.performQuery(PinComponent.query)
        
        if checkGameOver(pins: pins){
            NotificationCenter.default.post(name:PinSystem.gameOverNotification, object: nil)
        }
        
    }
    
    private func checkGameOver(pins: QueryResult<Entity>) -> Bool{
        let upVector = SIMD3<Float>(0,1,0)
        
        for pin in pins{
            let pinUpVector = pin.transform.matrix.columns.1.xyz
            
            if dot(pinUpVector, upVector) > 0.9{
                return false
            }
        }
        
        return true
    }
}

struct PinComponent: Component {
    static let query = EntityQuery(where: .has(PinComponent.self))
}

class ARGameView: ARView {
    func startApplyingForce(direction: ForceDirection){
//        print("apply force: \(direction.symbol)")
        
        if let ball = scene.performQuery(BallComponent.query).first{
            var ballState = ball.components[BallComponent.self] as? BallComponent
            ballState?.direction = direction
            ball.components[BallComponent.self] = ballState
//            print("START: Applied force:")
            
        }
        
        
    }
    func stopApplyingForce(){
//        print("stop applying force")
        if let ball = scene.performQuery(BallComponent.query).first{
            var ballState = ball.components[BallComponent.self] as? BallComponent
            ballState?.direction = nil
            ball.components[BallComponent.self] = ballState
//            print("STOP: Applied force:")

        }
    }
}

class BallPhysicsSystem: System {
    let ballSpeed: Float = 0.1
    required init(scene: RealityKit.Scene) {
            print("✅ BallPhysicsSystem registered successfully!")
    }
    
    func update(context: SceneUpdateContext) {
            // If within bounds, apply the movement impulse.
            if let ball = context.scene.performQuery(BallComponent.query).first{
//                print("Ball current coordinates: \(ball.transform.translation)")
                move(ball: ball)
            }
        }
    
    private func move(ball: Entity){
        guard let ballState = ball.components[BallComponent.self] as? BallComponent,
              let physicsBody = ball as? HasPhysicsBody else{
            return
        }
        
        if let forceDirection = ballState.direction?.vector {
            let impulse = ballSpeed * forceDirection
//            print("Applying impulse: \(impulse)")
            physicsBody.applyLinearImpulse(impulse, relativeTo: nil)
        }
    }
}

struct ControlsView : View{
    
    let startApplyingForce: (ForceDirection) -> Void
    let stopApplyingForce: () -> Void
    
    var body: some View {
        VStack{
            Spacer()
            HStack{
                Spacer()
                arrowButton(direction: .up)
                Spacer()
            }
            HStack{
                arrowButton(direction: .left)
                Spacer()
                arrowButton(direction: .right)
            }
            HStack{
                Spacer()
                arrowButton(direction: .down)
                Spacer()
            }
        }
        .padding(.horizontal)
    }
    func arrowButton(direction: ForceDirection) -> some View {
        Image(systemName: direction.symbol)
            .resizable()
            .frame(width: 75, height: 75)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged{ _ in
                        startApplyingForce(direction)
                    }
                    .onEnded{_ in
                        stopApplyingForce()
                    }
            )
    }
}

extension Sequence{
    var first: Element? {
        var iterator = self.makeIterator()
        return iterator.next()
    }
}
extension Entity {
    var descendants: [Entity] {
        var all = [Entity]()
        func addChildren(of entity: Entity) {
            for child in entity.children {
                all.append(child)
                addChildren(of: child)
            }
        }
        addChildren(of: self)
        return all
    }
}

extension SIMD4 where Scalar ==Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x: x,y: y,z: z)
    }
}



#if DEBUG
struct ContentView_Previews : PreviewProvider {
        static var previews: some View {
            ContentView()
        }
}
#endif
