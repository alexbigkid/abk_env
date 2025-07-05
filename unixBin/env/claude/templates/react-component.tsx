import React from 'react';

interface ${COMPONENT_NAME}Props {
  className?: string;
  children?: React.ReactNode;
}

export const ${COMPONENT_NAME}: React.FC<${COMPONENT_NAME}Props> = ({
  className = '',
  children,
  ...props
}) => {
  return (
    <div className={`${COMPONENT_NAME.toLowerCase()} ${className}`} {...props}>
      {children}
    </div>
  );
};

export default ${COMPONENT_NAME};