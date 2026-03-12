import React, { useRef } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { Sphere, Box, Torus } from '@react-three/drei';
import { motion } from 'framer-motion';

const FloatingShape = ({ position, color, shape = 'sphere', speed = 1 }) => {
  const meshRef = useRef();

  useFrame((state) => {
    if (meshRef.current) {
      meshRef.current.rotation.x += 0.01 * speed;
      meshRef.current.rotation.y += 0.01 * speed;
      meshRef.current.position.y = position[1] + Math.sin(state.clock.elapsedTime * speed) * 0.5;
    }
  });

  const ShapeComponent = {
    sphere: Sphere,
    box: Box,
    torus: Torus
  }[shape];

  return (
    <ShapeComponent
      ref={meshRef}
      position={position}
      args={shape === 'torus' ? [0.5, 0.2, 16, 32] : [0.5, 32, 32]}
    >
      <meshStandardMaterial color={color} transparent opacity={0.7} />
    </ShapeComponent>
  );
};

const FloatingElements = ({ className = '' }) => {
  return (
    <motion.div 
      className={'floating-canvas ' + className}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 2 }}
    >
      <Canvas camera={{ position: [0, 0, 5] }}>
        <ambientLight intensity={0.5} />
        <pointLight position={[10, 10, 10]} />
        
        <FloatingShape position={[-2, 1, 0]} color=#0a66c2 shape=sphere speed={0.8} />
        <FloatingShape position={[2, -1, -1]} color=#ff6b6b shape=box speed={1.2} />
        <FloatingShape position={[0, 2, -2]} color=#4ecdc4 shape=torus speed={0.6} />
        <FloatingShape position={[-1, -2, 1]} color=#45b7d1 shape=sphere speed={1.0} />
        <FloatingShape position={[3, 0, 0]} color=#96ceb4 shape=box speed={0.9} />
      </Canvas>
    </motion.div>
  );
};

export default FloatingElements;
