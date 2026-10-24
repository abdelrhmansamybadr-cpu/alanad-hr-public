import * as THREE from 'three';

class GlowingSphere {
  private scene: THREE.Scene;
  private camera: THREE.PerspectiveCamera;
  private renderer: THREE.WebGLRenderer;
  private sphere: THREE.Mesh;
  private glowMesh: THREE.Mesh;
  private mouseX = 0;
  private mouseY = 0;
  private targetRotationX = 0;
  private targetRotationY = 0;
  private currentRotationX = 0;
  private currentRotationY = 0;
  private isDragging = false;
  private lastMouseX = 0;
  private lastMouseY = 0;

  constructor(container: HTMLElement) {
    // Scene setup
    this.scene = new THREE.Scene();
    
    // Camera setup
    this.camera = new THREE.PerspectiveCamera(
      75,
      window.innerWidth / window.innerHeight,
      0.1,
      1000
    );
    this.camera.position.z = 4;

    // Renderer setup
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.setPixelRatio(window.devicePixelRatio);
    container.appendChild(this.renderer.domElement);

    // Create glowing sphere
    const sphereGeometry = new THREE.SphereGeometry(1.2, 64, 64);
    
    // Custom shader material for glowing effect
    const sphereMaterial = new THREE.ShaderMaterial({
      uniforms: {
        time: { value: 0 },
        color1: { value: new THREE.Color(0x00ffff) },
        color2: { value: new THREE.Color(0xff00ff) },
      },
      vertexShader: `
        varying vec3 vNormal;
        varying vec3 vPosition;
        
        void main() {
          vNormal = normalize(normalMatrix * normal);
          vPosition = position;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: `
        uniform float time;
        uniform vec3 color1;
        uniform vec3 color2;
        
        varying vec3 vNormal;
        varying vec3 vPosition;
        
        void main() {
          float fresnel = pow(1.0 - abs(dot(vNormal, vec3(0.0, 0.0, 1.0))), 2.0);
          float gradient = sin(vPosition.y * 3.0 + time) * 0.5 + 0.5;
          vec3 color = mix(color1, color2, gradient);
          float glow = fresnel * 1.5;
          gl_FragColor = vec4(color + vec3(glow * 0.5), 1.0);
        }
      `,
    });

    this.sphere = new THREE.Mesh(sphereGeometry, sphereMaterial);
    this.scene.add(this.sphere);

    // Create outer glow mesh
    const glowGeometry = new THREE.SphereGeometry(1.6, 32, 32);
    const glowMaterial = new THREE.ShaderMaterial({
      uniforms: {
        time: { value: 0 },
        color1: { value: new THREE.Color(0x00ffff) },
        color2: { value: new THREE.Color(0xff00ff) },
      },
      vertexShader: `
        varying vec3 vNormal;
        
        void main() {
          vNormal = normalize(normalMatrix * normal);
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: `
        uniform float time;
        uniform vec3 color1;
        uniform vec3 color2;
        
        varying vec3 vNormal;
        
        void main() {
          float intensity = pow(0.7 - dot(vNormal, vec3(0.0, 0.0, 1.0)), 2.0);
          float pulse = sin(time * 2.0) * 0.2 + 0.8;
          vec3 glowColor = mix(color1, color2, sin(time) * 0.5 + 0.5);
          gl_FragColor = vec4(glowColor, intensity * 0.6 * pulse);
        }
      `,
      transparent: true,
      blending: THREE.AdditiveBlending,
      side: THREE.BackSide,
    });

    this.glowMesh = new THREE.Mesh(glowGeometry, glowMaterial);
    this.scene.add(this.glowMesh);

    // Add ambient particles
    this.addParticles();

    // Event listeners
    this.setupEventListeners();

    // Handle window resize
    window.addEventListener('resize', this.onWindowResize.bind(this));

    // Start animation
    this.animate();
  }

  private addParticles(): void {
    const particleCount = 200;
    const positions = new Float32Array(particleCount * 3);
    
    for (let i = 0; i < particleCount; i++) {
      positions[i * 3] = (Math.random() - 0.5) * 10;
      positions[i * 3 + 1] = (Math.random() - 0.5) * 10;
      positions[i * 3 + 2] = (Math.random() - 0.5) * 10;
    }

    const particleGeometry = new THREE.BufferGeometry();
    particleGeometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));

    const particleMaterial = new THREE.PointsMaterial({
      color: 0x00ffff,
      size: 0.05,
      transparent: true,
      opacity: 0.8,
      blending: THREE.AdditiveBlending,
    });

    const particles = new THREE.Points(particleGeometry, particleMaterial);
    this.scene.add(particles);
  }

  private setupEventListeners(): void {
    const canvas = this.renderer.domElement;

    canvas.addEventListener('mousedown', (e) => {
      this.isDragging = true;
      this.lastMouseX = e.clientX;
      this.lastMouseY = e.clientY;
    });

    canvas.addEventListener('mouseup', () => {
      this.isDragging = false;
    });

    canvas.addEventListener('mouseleave', () => {
      this.isDragging = false;
    });

    canvas.addEventListener('mousemove', (e) => {
      if (this.isDragging) {
        const deltaX = e.clientX - this.lastMouseX;
        const deltaY = e.clientY - this.lastMouseY;
        
        this.targetRotationY += deltaX * 0.005;
        this.targetRotationX += deltaY * 0.005;
        
        this.lastMouseX = e.clientX;
        this.lastMouseY = e.clientY;
      } else {
        // Smooth follow when not dragging
        this.mouseX = (e.clientX / window.innerWidth) * 2 - 1;
        this.mouseY = (e.clientY / window.innerHeight) * 2 - 1;
        
        this.targetRotationY = this.mouseX * Math.PI * 0.5;
        this.targetRotationX = this.mouseY * Math.PI * 0.3;
      }
    });

    // Touch events for mobile
    canvas.addEventListener('touchstart', (e) => {
      this.isDragging = true;
      this.lastMouseX = e.touches[0].clientX;
      this.lastMouseY = e.touches[0].clientY;
    });

    canvas.addEventListener('touchend', () => {
      this.isDragging = false;
    });

    canvas.addEventListener('touchmove', (e) => {
      if (this.isDragging) {
        const deltaX = e.touches[0].clientX - this.lastMouseX;
        const deltaY = e.touches[0].clientY - this.lastMouseY;
        
        this.targetRotationY += deltaX * 0.005;
        this.targetRotationX += deltaY * 0.005;
        
        this.lastMouseX = e.touches[0].clientX;
        this.lastMouseY = e.touches[0].clientY;
      }
    });
  }

  private onWindowResize(): void {
    this.camera.aspect = window.innerWidth / window.innerHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(window.innerWidth, window.innerHeight);
  }

  private animate = (): void => {
    requestAnimationFrame(this.animate);

    const time = Date.now() * 0.001;

    // Smooth rotation interpolation
    this.currentRotationX += (this.targetRotationX - this.currentRotationX) * 0.05;
    this.currentRotationY += (this.targetRotationY - this.currentRotationY) * 0.05;

    // Apply rotation to sphere
    this.sphere.rotation.x = this.currentRotationX;
    this.sphere.rotation.y = this.currentRotationY;

    // Auto-spin effect
    this.sphere.rotation.y += 0.003;
    this.sphere.rotation.x += 0.001;

    // Update shader uniforms
    const sphereMaterial = this.sphere.material as THREE.ShaderMaterial;
    const glowMaterial = this.glowMesh.material as THREE.ShaderMaterial;
    
    sphereMaterial.uniforms.time.value = time;
    glowMaterial.uniforms.time.value = time;

    // Pulsing glow scale
    const glowScale = 1 + Math.sin(time * 2) * 0.05;
    this.glowMesh.scale.set(glowScale, glowScale, glowScale);

    this.renderer.render(this.scene, this.camera);
  };
}

// Initialize
const container = document.getElementById('app');
if (container) {
  new GlowingSphere(container);
}
