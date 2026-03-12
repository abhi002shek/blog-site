import React from 'react';
import { motion } from 'framer-motion';
import { useIntersectionObserver } from '../hooks/useIntersectionObserver';
import { sanitizeHTML } from '../utils/security';
import { fadeInUp, buttonHover } from '../utils/animations';

const BlogCard3D = ({ blog, onReadMore, index }) => {
  const { ref, hasIntersected } = useIntersectionObserver();

  const cardVariants = {
    hidden: { 
      opacity: 0, 
      y: 50,
      rotateX: -15,
      scale: 0.9
    },
    visible: { 
      opacity: 1, 
      y: 0,
      rotateX: 0,
      scale: 1,
      transition: { 
        duration: 0.6, 
        delay: index * 0.1,
        ease: easeOut
      }
    }
  };

  const hoverVariants = {
    whileHover: {
      y: -15,
      rotateX: 5,
      rotateY: 5,
      scale: 1.02,
      transition: { duration: 0.3 }
    }
  };

  return (
    <motion.div
      ref={ref}
      className=blog-card-3d
      variants={cardVariants}
      initial=hidden
      animate={hasIntersected ? visible : hidden}
      {...hoverVariants}
    >
      <div className=card-glow></div>
      
      <motion.div 
        className=card-image-container
        whileHover={{ scale: 1.1 }}
        transition={{ duration: 0.3 }}
      >
        <img
          src={blog.image}
          alt={blog.destination}
          className=card-image-3d
          loading=lazy
        />
        <div className=image-overlay></div>
      </motion.div>

      <div className=card-content-3d>
        <motion.h3 
          className=card-title-3d
          initial={{ opacity: 0, y: 20 }}
          animate={hasIntersected ? { opacity: 1, y: 0 } : {}}
          transition={{ delay: 0.3 + index * 0.1 }}
        >
          {blog.destination}
        </motion.h3>

        <motion.p 
          className=card-text-3d
          initial={{ opacity: 0 }}
          animate={hasIntersected ? { opacity: 1 } : {}}
          transition={{ delay: 0.4 + index * 0.1 }}
          dangerouslySetInnerHTML={{
            __html: sanitizeHTML(blog.content.substring(0, 130) + '...')
          }}
        />

        <motion.div 
          className=card-footer-3d
          initial={{ opacity: 0, y: 20 }}
          animate={hasIntersected ? { opacity: 1, y: 0 } : {}}
          transition={{ delay: 0.5 + index * 0.1 }}
        >
          <span className=author-3d>
            <span className=author-icon>✍</span>
            {blog.author}
          </span>
          
          <motion.button 
            className=read-btn-3d
            onClick={() => onReadMore(blog)}
            {...buttonHover}
          >
            <span>Read More</span>
            <span className=btn-arrow>→</span>
          </motion.button>
        </motion.div>
      </div>
    </motion.div>
  );
};

export default BlogCard3D;
