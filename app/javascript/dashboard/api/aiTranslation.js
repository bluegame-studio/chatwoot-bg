/* global axios */

export default {
  authorize() {
    return axios.post('/api/v1/profile/ai_translation_authorization');
  },
  translate({ content, sourceLang, targetLang }) {
    return axios.post('/api/v1/profile/ai_translation', {
      content,
      sourceLang,
      targetLang,
    });
  },
};
