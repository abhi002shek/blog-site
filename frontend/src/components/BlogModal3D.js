import React from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { sanitizeHTML } from '../utils/security';

const BlogModal3D = ({ blog, isOpen, onClose }) => {
  const overlayVariants = {
    hidden: { opacity: 0 },
    visible: { opacity: 1 }
  };

  const modalVariants = {
    hidden: { 
      opacity: 0, 
      scale: 0.8,
      rotateX: -15,
      y: 100
    },
    visible: { 
      opacity: 1, 
      scale: 1,
      rotateX: 0,
      y: 0,
      transition: {
        type: spring,
        damping: 25,
        stiffness: 300
      }
    },
    exit: {
      opacity: 0,
      scale: 0.8,
      rotateX: 15,
      y: -100,
      transition: { duration: 0.3 }
    }
  };

  if (!blog) return null;

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          className=modal-overlay-3d
          variants={overlayVariants}
          initial=hidden
          animate=visible
          exit=hidden
          onClick={onClose}
        >
          <motion.div
            className=modal-3d
            variants={modalVariants}
            initial=hidden
            animate=visible
            exit=exit
            onClick={(e) => e.stopPropagation()}
          >
            <div className=modal-glow></div>
            
            <motion.button
              className=close-btn-3d
              onClick={onClose}
              whileHover={{ scale: 1.1, rotate: 90 }}
              whileTap={{ scale: 0.9 }}
            >
              ✕
            </motion.button>

            <motion.div 
              className=modal-image-container
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.2 }}
            >
              <img
                src={blog.image}
                alt={blog.destination}
                className=modal-image-3d
              />
            </motion.div>

            <motion.div 
              className=modal-content-3d
              initial={{ opacity: 0, y: 30 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.3 }}
            >
              <h2 className=modal-title-3d>{blog.destination}</h2>
              
              <div className=modal-author-3d>
                <span className=author-icon>✍</span>
                By {blog.author}
              </div>

              <div 
                className=modal-text-3d
                dangerouslySetInnerHTML={{
                  __html: sanitizeHTML(blog.content)
                }}
              />
            </motion.div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};

export default BlogModal3D;
