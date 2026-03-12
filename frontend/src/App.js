import React, { useEffect, useState } from 'react';
import axios from 'axios';
import './App.css';

// Security utilities
const sanitizeInput = (input) => input.trim().replace(/[<>"']/g, '');
const validateURL = (url) => {
  try {
    const urlObj = new URL(url);
    return ['http:', 'https:'].includes(urlObj.protocol);
  } catch {
    return false;
  }
};

function App() {
  const [blogs, setBlogs] = useState([]);
  const [selectedBlog, setSelectedBlog] = useState(null);
  const [showModal, setShowModal] = useState(false);
  const [showBlogModal, setShowBlogModal] = useState(false);
  const [form, setForm] = useState({
    destination: '',
    content: '',
    author: '',
    image: ''
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const API = ;

  // Fetch blogs
  const fetchBlogs = async () => {
    try {
      setLoading(true);
      const res = await axios.get(API);
      setBlogs(res.data);
    } catch (error) {
      setError('Failed to fetch blogs');
      console.error('Error fetching blogs:', error);
    } finally {
      setLoading(false);
    }
  };

  // Handle submit with validation
  const handleSubmit = async (e) => {
    e.preventDefault();
    
    // Validate inputs
    if (!form.destination.trim() || !form.author.trim() || !form.content.trim() || !form.image.trim()) {
      setError('All fields are required');
      return;
    }
    
    if (!validateURL(form.image)) {
      setError('Please enter a valid image URL');
      return;
    }

    try {
      setLoading(true);
      setError('');
      
      const sanitizedForm = {
        destination: sanitizeInput(form.destination),
        content: sanitizeInput(form.content),
        author: sanitizeInput(form.author),
        image: form.image.trim()
      };

      const res = await axios.post(API, sanitizedForm);
      setBlogs([res.data, ...blogs]);
      setForm({ destination: '', content: '', author: '', image: '' });
      setShowModal(false);
    } catch (error) {
      setError('Failed to create blog');
      console.error('Error creating blog:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleReadMore = (blog) => {
    setSelectedBlog(blog);
    setShowBlogModal(true);
  };

  // Keyboard shortcuts
  useEffect(() => {
    const handleEsc = (e) => {
      if (e.key === 'Escape') {
        setShowModal(false);
        setShowBlogModal(false);
      }
    };
    window.addEventListener('keydown', handleEsc);
    return () => window.removeEventListener('keydown', handleEsc);
  }, []);

  useEffect(() => {
    fetchBlogs();
  }, []);

  return (
    <div className=app-container>
      {/* Floating background elements */}
      <div className=floating-bg>
        <div className=floating-shape shape-1></div>
        <div className=floating-shape shape-2></div>
        <div className=floating-shape shape-3></div>
        <div className=floating-shape shape-4></div>
      </div>

      {/* Navigation */}
      <nav className=navbar-3d>
        <div className=logo-3d>
          <span className=logo-text>Blog</span>
          <span className=logo-accent>Site</span>
        </div>
        <button
          className=create-btn-3d
          onClick={() => setShowModal(true)}
        >
          <span className=btn-icon>+</span>
          <span>Create Blog</span>
        </button>
      </nav>

      {/* Hero Section */}
      <section className=hero-3d>
        <div className=hero-overlay></div>
        <div className=hero-content-3d>
          <h1 className=hero-title>
            Explore the World
            <span className=title-accent>Through Stories</span>
          </h1>
          <p className=hero-subtitle>
            Share your journeys, inspire others, and discover amazing destinations
          </p>
          <button
            className=hero-cta
            onClick={() => setShowModal(true)}
          >
            Start Your Journey
            <span className=cta-arrow>→</span>
          </button>
        </div>
        
        {/* Floating particles */}
        <div className=hero-particles>
          {[...Array(15)].map((_, i) => (
            <div
              key={i}
              className=particle
              style={{
                left: ,
                animationDelay: ,
                animationDuration: 
              }}
            />
          ))}
        </div>
      </section>

      {/* Blog Section */}
      <section className=blog-section-3d>
        <div className=section-header>
          <h2 className=section-title-3d>Latest Stories</h2>
          <div className=title-underline></div>
        </div>

        {error && (
          <div className=error-message>
            {error}
          </div>
        )}

        <div className=blog-grid-3d>
          {blogs.map((blog, index) => (
            <div
              key={blog._id}
              className=blog-card-3d
              style={{ animationDelay:  }}
            >
              <div className=card-glow></div>
              
              <div className=card-image-container>
                <img
                  src={blog.image}
                  alt={blog.destination}
                  className=card-image-3d
                  loading=lazy
                />
                <div className=image-overlay></div>
              </div>

              <div className=card-content-3d>
                <h3 className=card-title-3d>{blog.destination}</h3>
                <p className=card-text-3d>
                  {blog.content.substring(0, 130)}...
                </p>
                <div className=card-footer-3d>
                  <span className=author-3d>
                    <span className=author-icon>✍</span>
                    {blog.author}
                  </span>
                  <button 
                    className=read-btn-3d
                    onClick={() => handleReadMore(blog)}
                  >
                    <span>Read More</span>
                    <span className=btn-arrow>→</span>
                  </button>
                </div>
              </div>
            </div>
          ))}
        </div>

        {blogs.length === 0 && !loading && (
          <div className=empty-state>
            <div className=empty-icon>📝</div>
            <h3>No stories yet</h3>
            <p>Be the first to share your amazing journey!</p>
            <button
              className=empty-cta
              onClick={() => setShowModal(true)}
            >
              Create First Blog
            </button>
          </div>
        )}
      </section>

      {/* Loading indicator */}
      {loading && (
        <div className=loading-overlay>
          <div className=loading-spinner-3d></div>
        </div>
      )}

      {/* Create Blog Modal */}
      {showModal && (
        <div className=modal-overlay-3d onClick={() => setShowModal(false)}>
          <div className=create-modal-3d onClick={(e) => e.stopPropagation()}>
            <div className=modal-glow></div>
            
            <button
              className=close-btn-3d
              onClick={() => setShowModal(false)}
            >
              ✕
            </button>

            <h2 className=create-modal-title>Create New Blog</h2>

            <form onSubmit={handleSubmit} className=create-form-3d>
              <div className=form-group-3d>
                <label>Destination</label>
                <input
                  type=text
                  value={form.destination}
                  onChange={(e) => setForm({...form, destination: e.target.value})}
                  required
                />
              </div>

              <div className=form-group-3d>
                <label>Author Name</label>
                <input
                  type=text
                  value={form.author}
                  onChange={(e) => setForm({...form, author: e.target.value})}
                  required
                />
              </div>

              <div className=form-group-3d>
                <label>Image URL</label>
                <input
                  type=url
                  value={form.image}
                  onChange={(e) => setForm({...form, image: e.target.value})}
                  required
                />
              </div>

              <div className=form-group-3d>
                <label>Story</label>
                <textarea
                  rows=4
                  value={form.content}
                  onChange={(e) => setForm({...form, content: e.target.value})}
                  required
                />
              </div>

              <button
                type=submit
                className=publish-btn-3d
                disabled={loading}
              >
                {loading ? 'Publishing...' : 'Publish Blog'}
              </button>
            </form>
          </div>
        </div>
      )}

      {/* Blog Detail Modal */}
      {showBlogModal && selectedBlog && (
        <div className=modal-overlay-3d onClick={() => setShowBlogModal(false)}>
          <div className=modal-3d onClick={(e) => e.stopPropagation()}>
            <div className=modal-glow></div>
            
            <button
              className=close-btn-3d
              onClick={() => setShowBlogModal(false)}
            >
              ✕
            </button>

            <div className=modal-image-container>
              <img
                src={selectedBlog.image}
                alt={selectedBlog.destination}
                className=modal-image-3d
              />
            </div>

            <div className=modal-content-3d>
              <h2 className=modal-title-3d>{selectedBlog.destination}</h2>
              
              <div className=modal-author-3d>
                <span className=author-icon>✍</span>
                By {selectedBlog.author}
              </div>

              <div className=modal-text-3d>
                {selectedBlog.content}
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
