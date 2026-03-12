import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { sanitizeInput, validateURL } from '../utils/security';
import { buttonHover } from '../utils/animations';

const CreateBlogModal3D = ({ isOpen, onClose, onSubmit, loading }) => {
  const [form, setForm] = useState({
    destination: '',
    content: '',
    author: '',
    image: ''
  });
  const [errors, setErrors] = useState({});

  const validateForm = () => {
    const newErrors = {};
    
    if (!form.destination.trim()) newErrors.destination = 'Destination is required';
    if (!form.author.trim()) newErrors.author = 'Author name is required';
    if (!form.content.trim()) newErrors.content = 'Content is required';
    if (!form.image.trim()) {
      newErrors.image = 'Image URL is required';
    } else if (!validateURL(form.image)) {
      newErrors.image = 'Please enter a valid image URL';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    
    if (!validateForm()) return;

    const sanitizedForm = {
      destination: sanitizeInput(form.destination),
      content: sanitizeInput(form.content),
      author: sanitizeInput(form.author),
      image: form.image.trim()
    };

    onSubmit(sanitizedForm);
    setForm({ destination: '', content: '', author: '', image: '' });
    setErrors({});
  };

  const handleInputChange = (field, value) => {
    setForm(prev => ({ ...prev, [field]: value }));
    if (errors[field]) {
      setErrors(prev => ({ ...prev, [field]: '' }));
    }
  };

  const modalVariants = {
    hidden: { 
      opacity: 0, 
      scale: 0.8,
      rotateY: -15
    },
    visible: { 
      opacity: 1, 
      scale: 1,
      rotateY: 0,
      transition: {
        type: spring,
        damping: 25,
        stiffness: 300
      }
    },
    exit: {
      opacity: 0,
      scale: 0.8,
      rotateY: 15,
      transition: { duration: 0.3 }
    }
  };

  const inputVariants = {
    focus: { 
      scale: 1.02,
      transition: { duration: 0.2 }
    }
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          className=modal-overlay-3d
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={onClose}
        >
          <motion.div
            className=create-modal-3d
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

            <motion.h2 
              className=create-modal-title
              initial={{ opacity: 0, y: -20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.2 }}
            >
              Create New Blog
            </motion.h2>

            <form onSubmit={handleSubmit} className=create-form-3d>
              <motion.div 
                className=form-group-3d
                initial={{ opacity: 0, x: -30 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.3 }}
              >
                <label>Destination</label>
                <motion.input
                  type=text
                  value={form.destination}
                  onChange={(e) => handleInputChange('destination', e.target.value)}
                  className={errors.destination ? 'error' : ''}
                  variants={inputVariants}
                  whileFocus=focus
                  required
                />
                {errors.destination && <span className=error-text>{errors.destination}</span>}
              </motion.div>

              <motion.div 
                className=form-group-3d
                initial={{ opacity: 0, x: 30 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.4 }}
              >
                <label>Author Name</label>
                <motion.input
                  type=text
                  value={form.author}
                  onChange={(e) => handleInputChange('author', e.target.value)}
                  className={errors.author ? 'error' : ''}
                  variants={inputVariants}
                  whileFocus=focus
                  required
                />
                {errors.author && <span className=error-text>{errors.author}</span>}
              </motion.div>

              <motion.div 
                className=form-group-3d
                initial={{ opacity: 0, x: -30 }}
                animate={{ opacity: 1, x: 0 }}
                transition={{ delay: 0.5 }}
              >
                <label>Image URL</label>
                <motion.input
                  type=url
                  value={form.image}
                  onChange={(e) => handleInputChange('image', e.target.value)}
                  className={errors.image ? 'error' : ''}
                  variants={inputVariants}
                  whileFocus=focus
                  required
                />
                {errors.image && <span className=error-text>{errors.image}</span>}
              </motion.div>

              <motion.div 
                className=form-group-3d
                initial={{ opacity: 0, y: 30 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.6 }}
              >
                <label>Story</label>
                <motion.textarea
                  rows=4
                  value={form.content}
                  onChange={(e) => handleInputChange('content', e.target.value)}
                  className={errors.content ? 'error' : ''}
                  variants={inputVariants}
                  whileFocus=focus
                  required
                />
                {errors.content && <span className=error-text>{errors.content}</span>}
              </motion.div>

              <motion.button
                type=submit
                className=publish-btn-3d
                disabled={loading}
                {...buttonHover}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.7 }}
              >
                {loading ? (
                  <motion.div
                    className=loading-spinner
                    animate={{ rotate: 360 }}
                    transition={{ duration: 1, repeat: Infinity, ease: linear }}
                  />
                ) : (
                  'Publish Blog'
                )}
              </motion.button>
            </form>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};

export default CreateBlogModal3D;
